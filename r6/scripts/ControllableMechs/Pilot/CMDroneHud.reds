// =============================================================================
// MECHS OF NIGHT CITY - DRONE HUD (0.7.0)
//
// A drone's own display, after an MQ-1 sensor operator's (Omar's reference) but sparse:
// one phosphor green, thin lines, empty sky. Laid out on the same 2160-high design space
// as the mech HUD (CMPilotHud, whose small drawing helpers it uses):
//   top          heading tape, the heading boxed
//   left / right speed (m/s) and altitude (m above the ground) tapes, values boxed, and the
//                vertical speed
//   centre       horizon wings and two pitch rungs that pitch and roll with the drone, the
//                sensor's gapped crosshair and its laser range; the mortar's predicted
//                impact (hidden until the weapons are in)
//   top left     the drone, its role and sensor; the link and range
//   top right    pitch, roll, rotor spool
//   bottom left  weapons: up to three lines, the selected one boxed bright; the hold
//                mode's banner (GUNSHIP) under the heading tape
//   bottom right the damage schematic (the Octant's, top-down, a layer per part coloured by
//                its health and greyed when destroyed) and the hull
// The session drives it through CMPilotHud's calls; the mech's own pieces aren't built.
// No field may share a name with one of CMPilotHud's (private or not): the scripts compile,
// but the game then refuses to start ("Failed to initialize scripts data", a49).
// =============================================================================
module ControllableMechs

import Codeware.UI.ScreenHelper

public class CMDroneHud extends CMPilotHud {
  private let m_kind: String;
  private let m_droot: ref<inkCanvas>;
  private let m_dparent: wref<inkCompoundWidget>;
  private let m_dhidden: array<wref<inkWidget>>;
  private let m_dhiddenOp: array<Float>;
  private let m_W: Float;            // the design space's width (2160 high)
  private let m_bootLeft: Float;

  private let m_hdgTicks: array<ref<inkRectangle>>;
  private let m_hdgLabels: array<ref<inkText>>;
  private let m_hdgBox: ref<inkText>;
  private let m_speedText: ref<inkText>;
  private let m_altText: ref<inkText>;
  private let m_vsText: ref<inkText>;
  private let m_horizon: ref<inkCanvas>;
  private let m_lrf: ref<inkText>;
  private let m_name: ref<inkText>;
  private let m_role: ref<inkText>;
  private let m_linkT: ref<inkText>;
  private let m_pitchT: ref<inkText>;
  private let m_rollT: ref<inkText>;
  private let m_spoolT: ref<inkText>;
  private let m_pri: ref<inkText>;
  private let m_sec: ref<inkText>;
  private let m_priBox: ref<inkCanvas>;
  private let m_secBox: ref<inkCanvas>;
  private let m_ter: ref<inkText>;
  private let m_terBox: ref<inkCanvas>;
  private let m_holdT: ref<inkText>;
  private let m_heat: ref<inkRectangle>;
  private let m_hullT: ref<inkText>;
  private let m_hullBar: ref<inkRectangle>;
  private let m_warnT: ref<inkText>;
  private let m_impact: ref<inkCanvas>;
  private let m_impactT: ref<inkText>;
  private let m_zoomT: ref<inkText>;
  private let m_cross: ref<inkCanvas>;
  private let m_schemParts: array<ref<inkImage>>;
  private let m_schemNames: array<CName>;
  private let m_flashT: Float;

  private let HZ_PX: Float = 10.0;    // px per degree on the horizon
  private let HDG_PX: Float = 6.0;       // px per degree on the heading tape
  private let SCHEM_H: Float = 430.0;    // the damage schematic's height on screen

  public static func Atlas() -> ResRef = r"mnc\\hud\\drone_schematics.inkatlas"

  public func SetKind(kind: String) -> Void {
    this.m_kind = kind;
  }

  // ---------------------------------------------------------------------------
  public func Build() -> Bool {
    let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
    if !IsDefined(layer) {
      return false;
    }
    let window = layer.GetVirtualWindow();
    if !IsDefined(window) {
      return false;
    }
    this.m_dparent = window;
    // the vanilla HUD hidden while linked, as the mech's HUD does
    ArrayClear(this.m_dhidden);
    ArrayClear(this.m_dhiddenOp);
    let i = 0;
    while i < window.GetNumChildren() {
      let child = window.GetWidgetByIndex(i);
      if IsDefined(child) && NotEquals(child.GetName(), n"cm_drone_hud") {
        ArrayPush(this.m_dhidden, child);
        ArrayPush(this.m_dhiddenOp, child.GetOpacity());
        child.SetOpacity(0.0);
      }
      i += 1;
    }
    let root = new inkCanvas();
    root.SetName(n"cm_drone_hud");
    root.SetInteractive(false);
    let screen = ScreenHelper.GetScreenSize(GetGameInstance());
    this.m_W = 3840.0;
    if screen.Y > 100.0 {
      let k = screen.Y / 2160.0;
      this.m_W = screen.X / k;
      root.SetAnchor(inkEAnchor.TopLeft);
      root.SetSize(Vector2(this.m_W, 2160.0));
      root.SetRenderTransformPivot(Vector2(0.0, 0.0));
      root.SetScale(Vector2(k, k));
    } else {
      root.SetAnchor(inkEAnchor.Fill);
    }
    root.Reparent(window);
    this.m_droot = root;
    this.BuildCorners(root);
    this.BuildHeading(root);
    this.BuildTapes(root);
    this.BuildCentre(root);
    this.BuildBlocks(root);
    this.BuildWeapons(root);
    this.BuildDamage(root);
    return true;
  }

  public func Remove() -> Void {
    if IsDefined(this.m_droot) && IsDefined(this.m_dparent) {
      this.m_droot.StopAllAnimations();
      this.m_dparent.RemoveChild(this.m_droot);
    }
    this.m_droot = null;
    let i = 0;
    while i < ArraySize(this.m_dhidden) {
      let w = this.m_dhidden[i];
      if IsDefined(w) {
        w.SetOpacity(this.m_dhiddenOp[i]);
      }
      i += 1;
    }
    ArrayClear(this.m_dhidden);
    ArrayClear(this.m_dhiddenOp);
    ArrayClear(this.m_schemParts);
  }

  // ---- drawing -----------------------------------------------------------------
  private func G() -> HDRColor = CMPilotHud.Amber()
  private func Line(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, op: Float) -> ref<inkRectangle> = CMPilotHud.Bar(root, x, y, w, h, this.G(), op)
  private func Txt(root: ref<inkCanvas>, x: Float, y: Float, text: String, size: Int32, centred: Bool) -> ref<inkText> {
    let t = CMPilotHud.Label(root, inkEAnchor.TopLeft, x, y, text, size, n"Medium", this.G());
    if centred {
      t.SetAnchorPoint(Vector2(0.5, 0.0));
    }
    return t;
  }
  // an outlined box
  private func Frame(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, op: Float) -> ref<inkCanvas> {
    let c = new inkCanvas();
    c.SetMargin(inkMargin(x, y, 0.0, 0.0));
    c.SetSize(Vector2(w, h));
    c.Reparent(root);
    this.Line(c, 0.0, 0.0, w, 3.0, op);
    this.Line(c, 0.0, h - 3.0, w, 3.0, op);
    this.Line(c, 0.0, 0.0, 3.0, h, op);
    this.Line(c, w - 3.0, 0.0, 3.0, h, op);
    return c;
  }

  private func BuildCorners(root: ref<inkCanvas>) -> Void {
    let W = this.m_W;
    let L = 200.0;
    let m = 80.0;
    this.Line(root, m, m, L, 3.0, 0.5);
    this.Line(root, m, m, 3.0, L, 0.5);
    this.Line(root, W - m - L, m, L, 3.0, 0.5);
    this.Line(root, W - m - 3.0, m, 3.0, L, 0.5);
    this.Line(root, m, 2160.0 - m - 3.0, L, 3.0, 0.5);
    this.Line(root, m, 2160.0 - m - L, 3.0, L, 0.5);
    this.Line(root, W - m - L, 2160.0 - m - 3.0, L, 3.0, 0.5);
    this.Line(root, W - m - 3.0, 2160.0 - m - L, 3.0, L, 0.5);
  }

  // the heading tape: a tick every 5 deg (long every 10), a label every 30
  private func BuildHeading(root: ref<inkCanvas>) -> Void {
    let cx = this.m_W * 0.5;
    this.Line(root, cx - 600.0, 190.0, 1200.0, 3.0, 0.9);
    let i = 0;
    while i < 41 {
      ArrayPush(this.m_hdgTicks, this.Line(root, cx, 170.0, 3.0, 20.0, 0.9));
      i += 1;
    }
    i = 0;
    while i < 5 {
      ArrayPush(this.m_hdgLabels, this.Txt(root, cx, 126.0, "000", 30, true));
      i += 1;
    }
    this.Frame(root, cx - 85.0, 66.0, 170.0, 58.0, 1.0);
    this.m_hdgBox = this.Txt(root, cx, 72.0, "000", 42, true);
    // the caret under the tape
    this.Line(root, cx - 1.5, 196.0, 3.0, 26.0, 1.0);
  }

  public func SetAttitude(heading: Float, pitch: Float) -> Void {
    if !IsDefined(this.m_droot) {
      return;
    }
    let h = heading;
    while h < 0.0 {
      h += 360.0;
    }
    let cx = this.m_W * 0.5;
    let base = FloorF(h / 5.0) * 5;
    let i = 0;
    while i < ArraySize(this.m_hdgTicks) {
      let deg = Cast<Float>(base + (i - 20) * 5);
      let x = cx + (deg - h) * this.HDG_PX;
      let t = this.m_hdgTicks[i];
      let long = (base + (i - 20) * 5) % 10 == 0;
      t.SetVisible(AbsF(x - cx) <= 600.0);
      t.SetMargin(inkMargin(x - 1.5, long ? 166.0 : 176.0, 0.0, 0.0));
      t.SetSize(Vector2(3.0, long ? 24.0 : 14.0));
      i += 1;
    }
    let lbase = FloorF(h / 30.0) * 30;
    i = 0;
    while i < ArraySize(this.m_hdgLabels) {
      let deg = lbase + (i - 2) * 30;
      let x = cx + (Cast<Float>(deg) - h) * this.HDG_PX;
      let l = this.m_hdgLabels[i];
      l.SetVisible(AbsF(x - cx) <= 560.0 && AbsF(x - cx) > 70.0);
      l.SetMargin(inkMargin(x, 126.0, 0.0, 0.0));
      let d = deg % 360;
      if d < 0 {
        d += 360;
      }
      l.SetText(IntToString(d / 10));
      i += 1;
    }
    this.m_hdgBox.SetText(CMPilotHud.Pad3(RoundF(h) % 360));
  }

  // speed and altitude: a ladder with a boxed value at the middle
  private func BuildTapes(root: ref<inkCanvas>) -> Void {
    let cx = this.m_W * 0.5;
    let xl = cx - 1050.0;
    let xr = cx + 1050.0;
    this.Line(root, xl, 600.0, 3.0, 960.0, 0.8);
    this.Line(root, xr, 600.0, 3.0, 960.0, 0.8);
    let y = 600.0;
    let n = 0;
    while y <= 1560.0 {
      let long = n % 2 == 0;
      this.Line(root, xl, y, long ? 30.0 : 18.0, 3.0, 0.8);
      this.Line(root, xr - (long ? 27.0 : 15.0), y, long ? 30.0 : 18.0, 3.0, 0.8);
      y += 80.0;
      n += 1;
    }
    this.Txt(root, xl + 20.0, 548.0, "M/S", 28, true);
    this.Txt(root, xr - 20.0, 548.0, "ALT M", 28, true);
    this.Frame(root, xl - 210.0, 1050.0, 190.0, 62.0, 1.0);
    this.Frame(root, xr + 20.0, 1050.0, 190.0, 62.0, 1.0);
    this.m_speedText = this.Txt(root, xl - 115.0, 1056.0, "0.0", 42, true);
    this.m_altText = this.Txt(root, xr + 115.0, 1056.0, "000", 42, true);
    this.m_vsText = this.Txt(root, xr + 115.0, 1124.0, "VS 0.0", 28, true);
  }

  // the horizon (it pitches and rolls with the drone), the crosshair, the laser range and
  // the mortar's impact marker
  private func BuildCentre(root: ref<inkCanvas>) -> Void {
    let cx = this.m_W * 0.5;
    let hz = new inkCanvas();
    hz.SetMargin(inkMargin(cx - 600.0, 1080.0 - 400.0, 0.0, 0.0));
    hz.SetSize(Vector2(1200.0, 800.0));
    hz.SetRenderTransformPivot(Vector2(0.5, 0.5));
    hz.Reparent(root);
    this.m_horizon = hz;
    // wings at 0 deg, with their short drops
    this.Line(hz, 200.0, 400.0, 240.0, 4.0, 1.0);
    this.Line(hz, 436.0, 400.0, 4.0, 24.0, 1.0);
    this.Line(hz, 760.0, 400.0, 240.0, 4.0, 1.0);
    this.Line(hz, 760.0, 400.0, 4.0, 24.0, 1.0);
    // +10 deg solid, -10 deg dashed
    let up = 400.0 - 10.0 * this.HZ_PX;
    let dn = 400.0 + 10.0 * this.HZ_PX;
    this.Line(hz, 280.0, up, 160.0, 3.0, 0.55);
    this.Line(hz, 760.0, up, 160.0, 3.0, 0.55);
    let x = 280.0;
    while x < 440.0 {
      this.Line(hz, x, dn, 22.0, 3.0, 0.55);
      this.Line(hz, x + 480.0, dn, 22.0, 3.0, 0.55);
      x += 36.0;
    }
    this.Txt(hz, 950.0, up - 18.0, "10", 26, false).SetOpacity(0.55);
    this.Txt(hz, 950.0, dn - 18.0, "-10", 26, false).SetOpacity(0.55);
    // the sensor's crosshair: gapped, a centre point
    let c = new inkCanvas();
    c.SetMargin(inkMargin(cx - 120.0, 1080.0 - 120.0, 0.0, 0.0));
    c.SetSize(Vector2(240.0, 240.0));
    c.Reparent(root);
    this.m_cross = c;
    this.Line(c, 118.5, 0.0, 3.0, 90.0, 1.0);
    this.Line(c, 118.5, 150.0, 3.0, 90.0, 1.0);
    this.Line(c, 0.0, 118.5, 90.0, 3.0, 1.0);
    this.Line(c, 150.0, 118.5, 90.0, 3.0, 1.0);
    this.Line(c, 116.0, 116.0, 8.0, 8.0, 1.0);
    this.m_lrf = this.Txt(root, cx, 1080.0 + 150.0, "LRF ---- M", 36, true);
    this.m_zoomT = this.Txt(root, cx, 1080.0 + 196.0, "", 28, true);
    // the mortar's predicted impact: four amber corners round the spot, its time of flight
    let im = new inkCanvas();
    im.SetSize(Vector2(160.0, 80.0));
    im.SetVisible(false);
    im.Reparent(root);
    let a = CMPilotHud.Caution();
    CMPilotHud.Bar(im, 0.0, 0.0, 40.0, 3.0, a, 1.0);
    CMPilotHud.Bar(im, 0.0, 0.0, 3.0, 20.0, a, 1.0);
    CMPilotHud.Bar(im, 120.0, 0.0, 40.0, 3.0, a, 1.0);
    CMPilotHud.Bar(im, 157.0, 0.0, 3.0, 20.0, a, 1.0);
    CMPilotHud.Bar(im, 0.0, 77.0, 40.0, 3.0, a, 1.0);
    CMPilotHud.Bar(im, 0.0, 60.0, 3.0, 20.0, a, 1.0);
    CMPilotHud.Bar(im, 120.0, 77.0, 40.0, 3.0, a, 1.0);
    CMPilotHud.Bar(im, 157.0, 60.0, 3.0, 20.0, a, 1.0);
    this.m_impact = im;
    this.m_impactT = CMPilotHud.Label(im, inkEAnchor.TopLeft, 180.0, 18.0, "", 28, n"Medium", a);
  }

  // the mortar's predicted impact on screen (4K units from the centre), and its time of
  // flight; hidden when there's no solution
  public func SetImpact(on: Bool, x: Float, y: Float, tof: Float) -> Void {
    if !IsDefined(this.m_impact) {
      return;
    }
    this.m_impact.SetVisible(on);
    if on {
      this.m_impact.SetMargin(inkMargin(this.m_W * 0.5 + x - 80.0, 1080.0 + y - 40.0, 0.0, 0.0));
      this.m_impactT.SetText("IMPACT T+" + FloatToStringPrec(tof, 1) + " S");
    }
  }

  private func BuildBlocks(root: ref<inkCanvas>) -> Void {
    let W = this.m_W;
    this.m_name = this.Txt(root, 160.0, 150.0, "DRONE", 40, false);
    this.m_role = this.Txt(root, 160.0, 204.0, "", 30, false);
    this.m_linkT = this.Txt(root, 160.0, 248.0, "", 30, false);
    this.m_pitchT = this.Txt(root, W - 520.0, 150.0, "PITCH  +00", 30, false);
    this.m_rollT = this.Txt(root, W - 520.0, 194.0, "ROLL   +00", 30, false);
    this.m_spoolT = this.Txt(root, W - 520.0, 238.0, "SPOOL  00%", 30, false);
    this.m_warnT = this.Txt(root, W * 0.5, 300.0, "", 36, true);
    this.m_warnT.SetTintColor(CMPilotHud.Red());
  }

  // three weapon lines (the third hidden when the drone has two), the selected one bright
  private func BuildWeapons(root: ref<inkCanvas>) -> Void {
    this.m_priBox = this.Frame(root, 150.0, 1680.0, 760.0, 66.0, 1.0);
    this.m_secBox = this.Frame(root, 150.0, 1760.0, 760.0, 66.0, 1.0);
    this.m_terBox = this.Frame(root, 150.0, 1840.0, 760.0, 66.0, 1.0);
    this.m_pri = this.Txt(root, 176.0, 1688.0, "", 38, false);
    this.m_sec = this.Txt(root, 176.0, 1768.0, "", 38, false);
    this.m_ter = this.Txt(root, 176.0, 1848.0, "", 38, false);
    // the secondary's heat, along the bottom of its box
    this.m_heat = CMPilotHud.Bar(root, 152.0, 1818.0, 0.0, 6.0, CMPilotHud.Caution(), 1.0);
    this.Txt(root, 176.0, 1930.0, "[LMB] FIRE   [B] SELECT   [G] MISSILE   [H] GUNSHIP   [RMB] ZOOM   [T] SENSOR", 26, false).SetOpacity(0.55);
    // the hold mode's banner, under the heading
    this.m_holdT = this.Txt(root, this.m_W * 0.5, 244.0, "", 34, true);
    this.m_holdT.SetTintColor(CMPilotHud.Caution());
  }

  // the damage schematic, its parts from the atlas (tools/drones/schematic.py: each part's
  // place in the whole, in its 537 x 560 composite), and the hull under it
  private func BuildDamage(root: ref<inkCanvas>) -> Void {
    let W = this.m_W;
    let x0 = W - 170.0 - 537.0 * (this.SCHEM_H / 560.0);
    let y0 = 1520.0;
    if Equals(this.m_kind, "octant") {
      let k = this.SCHEM_H / 560.0;
      let box = new inkCanvas();
      box.SetMargin(inkMargin(x0, y0, 0.0, 0.0));
      box.SetSize(Vector2(537.0 * k, this.SCHEM_H));
      box.Reparent(root);
      this.Part(box, k, n"octant_body", 43.0, 15.0, 451.0, 540.0);
      this.Part(box, k, n"octant_thruster_fl", 5.0, 137.0, 132.0, 138.0);
      this.Part(box, k, n"octant_thruster_fr", 401.0, 137.0, 132.0, 138.0);
      this.Part(box, k, n"octant_thruster_bl", 11.0, 310.0, 126.0, 136.0);
      this.Part(box, k, n"octant_thruster_br", 400.0, 310.0, 127.0, 136.0);
      this.Part(box, k, n"octant_gun", 242.0, 5.0, 53.0, 56.0);
    }
    this.m_hullT = this.Txt(root, x0, 1960.0, "HULL 100%", 30, false);
    this.Frame(root, x0 + 200.0, 1966.0, 300.0, 24.0, 0.9);
    this.m_hullBar = this.Line(root, x0 + 204.0, 1970.0, 292.0, 16.0, 1.0);
  }

  private func Part(box: ref<inkCanvas>, k: Float, name: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
    let img = new inkImage();
    img.SetAtlasResource(CMDroneHud.Atlas());
    img.SetTexturePart(name);
    img.SetMargin(inkMargin(x * k, y * k, 0.0, 0.0));
    img.SetSize(Vector2(w * k, h * k));
    img.SetTintColor(this.G());
    img.SetInteractive(false);
    img.Reparent(box);
    ArrayPush(this.m_schemParts, img);
    ArrayPush(this.m_schemNames, name);
  }

  // ---- each frame / tick -----------------------------------------------------------
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.m_droot) {
      return;
    }
    this.m_name.SetText(s.title);
    this.m_role.SetText(s.role + " // SENSOR " + s.sensor);
    this.m_linkT.SetText("LINK " + IntToString(RoundF(s.signal * 100.0)) + "%   RNG " + FloatToStringPrec(s.distance / 1000.0, 2) + " KM");

    this.m_lrf.SetText(s.range > 0.0 && s.range < 2000.0 ? "LRF " + CMPilotHud.Pad4(RoundF(s.range)) + " M" : "LRF ---- M");
    this.m_zoomT.SetText(s.zoomed ? "ZOOM" : "");
    this.m_spoolT.SetText("SPOOL  " + IntToString(RoundF(s.spool * 100.0)) + "%");
    // weapons: the selected one boxed bright
    this.m_pri.SetText(s.priText);
    this.m_sec.SetText(s.secText);
    this.m_ter.SetText(s.terText);
    this.m_ter.SetVisible(StrLen(s.terText) > 0);
    this.m_terBox.SetVisible(StrLen(s.terText) > 0);
    this.m_priBox.SetOpacity(s.weapon == 0 ? 1.0 : 0.25);
    this.m_secBox.SetOpacity(s.weapon == 1 ? 1.0 : 0.25);
    this.m_terBox.SetOpacity(s.weapon == 2 ? 1.0 : 0.25);
    this.m_holdT.SetText(s.holdText);
    this.m_heat.SetSize(Vector2(756.0 * ClampF(s.secHeat, 0.0, 1.0), 6.0));
    this.m_heat.SetTintColor(s.secHeat >= 1.0 ? CMPilotHud.Red() : CMPilotHud.Caution());
    // hull and parts
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.m_hullT.SetText("HULL " + IntToString(RoundF(hull * 100.0)) + "%");
    this.m_hullBar.SetSize(Vector2(292.0 * hull, 16.0));
    this.m_hullBar.SetTintColor(CMDroneHud.Health(hull));
    let i = 0;
    while i < ArraySize(this.m_schemParts) {
      let hp = i < ArraySize(s.droneParts) ? s.droneParts[i] : 1.0;
      let img = this.m_schemParts[i];
      img.SetTintColor(hp <= 0.0 ? CMPilotHud.Grey() : CMDroneHud.Health(hp));
      img.SetOpacity(hp <= 0.0 ? 0.45 : 1.0);
      i += 1;
    }
    this.m_warnT.SetText(s.warning);
  }

  // every frame from the drone: its attitude on the horizon, and the flight numbers (the
  // session's refresh runs ten times a second, too coarse for a horizon)
  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.m_droot) {
      return;
    }
    this.m_horizon.SetRotation(-roll);
    this.m_horizon.SetMargin(inkMargin(this.m_W * 0.5 - 600.0, 1080.0 - 400.0 + ClampF(pitch, -35.0, 35.0) * this.HZ_PX, 0.0, 0.0));
    this.m_pitchT.SetText("PITCH  " + CMDroneHud.Signed(pitch));
    this.m_rollT.SetText("ROLL   " + CMDroneHud.Signed(roll));
    this.m_speedText.SetText(FloatToStringPrec(speed, 1));
    this.m_altText.SetText(alt >= 0.0 ? CMPilotHud.Pad3(RoundF(alt)) : "---");
    this.m_vsText.SetText("VS " + (vs >= 0.0 ? "+" : "") + FloatToStringPrec(vs, 1));
  }

  // green, then amber under 60%, red under 30%
  public static func Health(hp: Float) -> HDRColor {
    if hp < 0.3 {
      return CMPilotHud.Red();
    }
    if hp < 0.6 {
      return CMPilotHud.Caution();
    }
    return CMPilotHud.Amber();
  }

  public static func Signed(v: Float) -> String {
    let n = RoundF(v);
    let a = Abs(n);
    return (n < 0 ? "-" : "+") + (a < 10 ? "0" : "") + IntToString(a);
  }

  // the boot: the display fades up over a second
  public func StartBoot() -> Void {
    this.m_bootLeft = 1.0;
    if IsDefined(this.m_droot) {
      this.m_droot.SetOpacity(0.0);
    }
  }

  public func Boot(dt: Float) -> Void {
    if IsDefined(this.m_droot) && this.m_bootLeft > 0.0 {
      this.m_bootLeft -= dt;
      this.m_droot.SetOpacity(ClampF(1.0 - this.m_bootLeft, 0.0, 1.0) * RandRangeF(0.7, 1.0));
      if this.m_bootLeft <= 0.0 {
        this.m_droot.SetOpacity(1.0);
      }
    }
    // the crosshair's hit flash fades
    if this.m_flashT > 0.0 && IsDefined(this.m_cross) {
      this.m_flashT -= dt;
      this.m_cross.SetTintColor(this.m_flashT > 0.0 ? CMPilotHud.Caution() : this.G());
    }
  }

  public func Tags(dt: Float) -> Void {}
  public func TagFlash(i: Int32) -> Void {}
  public func HitFrom(off: Float) -> Void {}
  public func SetOptics(on: Bool) -> Void {}

  // a hit the drone's weapons scored: the crosshair flashes amber
  public func Hit(kill: Bool) -> Void {
    this.m_flashT = kill ? 0.5 : 0.15;
  }

  public func PartHit(i: Int32) -> Void {}
  public func Damage(lost: Float) -> Void {}
}
