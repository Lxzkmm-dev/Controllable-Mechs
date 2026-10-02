// =============================================================================
// MECHS OF NIGHT CITY - DRONE HUD: THE OCTANT'S GUNSHIP DISPLAY (0.7.1, round 2)
//
// A drone's own display, after an MQ-1 sensor operator's (Omar's reference): one phosphor
// green, thin lines. Laid out on the same 2160-high design space as the mech HUD
// (CMPilotHud, whose small drawing helpers it uses). Round 2 (Omar's mockup) keeps the MQ-1
// core and builds a gunship operator's screen round it:
//   top          heading tape, the heading boxed; a threat's bearing beside it when the
//                drone is shot at (HitFrom)
//   left / right speed (m/s) and altitude (m above the ground) tapes, values boxed, and the
//                vertical speed
//   centre       horizon wings and two pitch rungs that pitch and roll with the drone, the
//                sensor's gapped crosshair, its laser range and its azimuth / elevation;
//                the mortar's predicted impact, its time of flight and splash
//   top left     the sensor block: the drone, the sensor's mode and field of view, the
//                target's grid, the laser range, slant range and elevation, LASE
//   top right    the game's day and time, the link, pitch / roll, spool and the clock, wind
//   left         the map: north up, the drone, its sensor line to the reticle's point, V,
//                every contact the sweep found (CMDroneSense), the station it holds
//   bottom left  fire control: a row per station (mortar, LMG twin, Hydra pods), the
//                selected one lit, each with its status, heat or rockets and reload
//   bottom centre the BDA: kills, rounds, hits
//   bottom right the damage schematic (a layer per part coloured by its health, greyed when
//                destroyed), each part's status, the hull
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
  private let m_windT: ref<inkText>;
  private let m_heat: ref<inkRectangle>;
  private let m_hullT: ref<inkText>;
  private let m_hullBar: ref<inkRectangle>;
  private let m_warnT: ref<inkText>;
  private let m_impact: ref<inkCanvas>;
  private let m_impactT: ref<inkText>;
  private let m_zoomT: ref<inkText>;
  private let m_cross: ref<inkCanvas>;
  private let m_schemParts: array<ref<inkWidget>>;
  private let m_schemNames: array<CName>;
  private let m_flashT: Float;
  // round 2 (the Octant's gunship display)
  private let m_ocTgt: ref<inkText>;
  private let m_ocLrf: ref<inkText>;
  private let m_ocLase: ref<inkCanvas>;
  private let m_ocTime: ref<inkText>;
  private let m_ocAtt: ref<inkText>;
  private let m_ocClockT: ref<inkText>;
  private let m_ocClock: Float;
  private let m_ocMap: ref<inkCanvas>;
  private let m_ocDots: array<ref<inkRectangle>>;
  private let m_ocSelf: ref<inkCanvas>;
  private let m_ocSight: ref<inkRectangle>;
  private let m_ocAimX: ref<inkCanvas>;
  private let m_ocStation: ref<inkCanvas>;
  private let m_ocMapT: ref<inkText>;
  private let m_ocRows: array<ref<inkCanvas>>;
  private let m_ocRowNames: array<ref<inkText>>;
  private let m_ocRowSubs: array<ref<inkText>>;
  private let m_ocRowStats: array<ref<inkText>>;
  private let m_ocRowArrows: array<ref<inkText>>;
  private let m_ocPips: array<ref<inkRectangle>>;     // the LMG's heat
  private let m_ocRkPips: array<ref<inkRectangle>>;   // the pods' rockets
  private let m_ocLoads: array<ref<inkRectangle>>;    // the mortar's and the pods' reload
  private let m_ocBda: ref<inkText>;
  private let m_ocKills: Int32;
  private let m_ocParts: array<ref<inkText>>;
  private let m_ocThreat: ref<inkText>;
  private let m_ocThreatTick: ref<inkRectangle>;
  private let m_ocThreatT: Float;
  private let m_ocThreatB: Float;
  private let m_ocHeading: Float;
  private let m_ocAz: ref<inkText>;
  private let OC_MAP: Float = 480.0;     // the map's side
  private let OC_MPX: Float = 2.0;       // its px per m

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
    this.BuildMap(root);
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
    ArrayClear(this.m_ocDots);
    ArrayClear(this.m_ocRows);
    ArrayClear(this.m_ocRowNames);
    ArrayClear(this.m_ocRowSubs);
    ArrayClear(this.m_ocRowStats);
    ArrayClear(this.m_ocRowArrows);
    ArrayClear(this.m_ocPips);
    ArrayClear(this.m_ocRkPips);
    ArrayClear(this.m_ocLoads);
    ArrayClear(this.m_ocParts);
  }

  // a dark panel and its corners
  private func OcPanel(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float) -> Void {
    CMPilotHud.Bar(root, x, y, w, h, CMPilotHud.Black(), 0.35);
    let L = 24.0;
    this.Line(root, x, y, L, 3.0, 0.9);
    this.Line(root, x, y, 3.0, L, 0.9);
    this.Line(root, x + w - L, y, L, 3.0, 0.9);
    this.Line(root, x + w - 3.0, y, 3.0, L, 0.9);
    this.Line(root, x, y + h - 3.0, L, 3.0, 0.9);
    this.Line(root, x, y + h - L, 3.0, L, 0.9);
    this.Line(root, x + w - L, y + h - 3.0, L, 3.0, 0.9);
    this.Line(root, x + w - 3.0, y + h - L, 3.0, L, 0.9);
  }

  // text anchored by its right edge
  private func OcRight(root: ref<inkCanvas>, x: Float, y: Float, text: String, size: Int32) -> ref<inkText> {
    let t = this.Txt(root, x, y, text, size, false);
    t.SetAnchorPoint(Vector2(1.0, 0.0));
    return t;
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
    // a threat's bearing: a red tick on the tape and its line beside it
    this.m_ocThreatTick = CMPilotHud.Bar(root, cx, 156.0, 8.0, 40.0, CMPilotHud.Red(), 1.0);
    this.m_ocThreatTick.SetVisible(false);
    this.m_ocThreat = this.Txt(root, cx + 640.0, 160.0, "", 32, false);
    this.m_ocThreat.SetTintColor(CMPilotHud.Red());
  }

  public func SetAttitude(heading: Float, pitch: Float) -> Void {
    if !IsDefined(this.m_droot) {
      return;
    }
    let h = heading;
    while h < 0.0 {
      h += 360.0;
    }
    this.m_ocHeading = h;
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
    this.m_ocAz = this.Txt(root, cx, 1080.0 + 236.0, "", 26, true);
    this.m_ocAz.SetOpacity(0.7);
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
      this.m_impactT.SetText("IMPACT T+" + FloatToStringPrec(tof, 1) + " S   //   SPLASH 5 M");
    }
  }

  // the sensor block (top left) and the time / link block (top right)
  private func BuildBlocks(root: ref<inkCanvas>) -> Void {
    let W = this.m_W;
    this.OcPanel(root, 140.0, 120.0, 800.0, 250.0);
    this.m_name = this.Txt(root, 170.0, 134.0, "DRONE", 40, false);
    this.m_name.SetTintColor(CMPilotHud.Pale());
    this.m_role = this.Txt(root, 170.0, 192.0, "", 30, false);
    this.m_ocTgt = this.Txt(root, 170.0, 238.0, "TGT  ----", 30, false);
    this.m_ocLrf = this.Txt(root, 170.0, 284.0, "LRF ----", 30, false);
    // LASE: lit while the laser has a return
    let lase = new inkCanvas();
    lase.SetMargin(inkMargin(790.0, 192.0, 0.0, 0.0));
    lase.SetSize(Vector2(120.0, 44.0));
    lase.Reparent(root);
    CMPilotHud.Bar(lase, 0.0, 0.0, 120.0, 44.0, this.G(), 0.9);
    let lt = CMPilotHud.Label(lase, inkEAnchor.TopLeft, 60.0, 2.0, "LASE", 32, n"Semi-Bold", CMPilotHud.Black());
    lt.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_ocLase = lase;
    this.OcPanel(root, W - 940.0, 120.0, 800.0, 296.0);
    this.m_ocTime = this.OcRight(root, W - 170.0, 134.0, "", 40);
    this.m_ocTime.SetTintColor(CMPilotHud.Pale());
    this.m_linkT = this.OcRight(root, W - 170.0, 192.0, "", 30);
    this.m_ocAtt = this.OcRight(root, W - 170.0, 238.0, "", 30);
    this.m_ocClockT = this.OcRight(root, W - 170.0, 284.0, "", 30);
    this.m_windT = this.OcRight(root, W - 170.0, 330.0, "", 28);
    this.m_windT.SetOpacity(0.75);
    // (kept for the old lines' callers)
    this.m_pitchT = this.Txt(root, 0.0, 0.0, "", 10, false);
    this.m_rollT = this.Txt(root, 0.0, 0.0, "", 10, false);
    this.m_spoolT = this.Txt(root, 0.0, 0.0, "", 10, false);
    this.m_pitchT.SetVisible(false);
    this.m_rollT.SetVisible(false);
    this.m_spoolT.SetVisible(false);
    this.m_warnT = this.Txt(root, W * 0.5, 300.0, "", 36, true);
    this.m_warnT.SetTintColor(CMPilotHud.Red());
  }

  // the map: north up round the drone, 2 px a metre, rings at 50 and 100 m
  private func BuildMap(root: ref<inkCanvas>) -> Void {
    let x = 160.0;
    let y = 520.0;
    let S = this.OC_MAP;
    this.OcPanel(root, x - 20.0, y - 20.0, S + 40.0, S + 90.0);
    let m = new inkCanvas();
    m.SetMargin(inkMargin(x, y, 0.0, 0.0));
    m.SetSize(Vector2(S, S));
    m.Reparent(root);
    this.m_ocMap = m;
    let c = S * 0.5;
    CMInk.Ring(m, c, c, 50.0 * this.OC_MPX, 48, 2.0, this.G(), 0.35);
    CMInk.Ring(m, c, c, 100.0 * this.OC_MPX, 72, 2.0, this.G(), 0.35);
    this.Line(m, c - 1.0, 10.0, 2.0, S - 20.0, 0.15);
    this.Line(m, 10.0, c - 1.0, S - 20.0, 2.0, 0.15);
    this.Txt(m, c, -8.0, "N", 28, true);
    // the sensor's line to the reticle's point, and that point
    this.m_ocSight = CMPilotHud.Bar(m, c, c, 1.0, 3.0, this.G(), 0.8);
    let ax = new inkCanvas();
    ax.SetSize(Vector2(28.0, 28.0));
    ax.Reparent(m);
    CMPilotHud.Bar(ax, 12.5, 0.0, 3.0, 28.0, CMPilotHud.Caution(), 1.0);
    CMPilotHud.Bar(ax, 0.0, 12.5, 28.0, 3.0, CMPilotHud.Caution(), 1.0);
    this.m_ocAimX = ax;
    // the station the gunship hold keeps
    let st = new inkCanvas();
    st.SetSize(Vector2(40.0, 40.0));
    st.Reparent(m);
    CMInk.Ring(st, 20.0, 20.0, 16.0, 16, 3.0, this.G(), 0.9);
    this.m_ocStation = st;
    // the contacts
    let i = 0;
    while i < 32 {
      let d = CMPilotHud.Bar(m, 0.0, 0.0, 14.0, 14.0, this.G(), 1.0);
      d.SetVisible(false);
      ArrayPush(this.m_ocDots, d);
      i += 1;
    }
    // the drone at the middle, pointing where it looks
    this.m_ocSelf = CMInk.Chevron(m, 36.0, 5.0, CMPilotHud.Pale());
    this.m_ocSelf.SetMargin(inkMargin(c - 18.0, c - 18.0, 0.0, 0.0));
    this.m_ocMapT = this.Txt(root, x, y + S + 18.0, "", 26, false);
  }

  // fire control: a row per station (mortar, LMG twin, Hydra pods), the selected one lit;
  // the LMG's heat and the pods' rockets as pips, the mortar's and the pods' reload as bars
  private func BuildWeapons(root: ref<inkCanvas>) -> Void {
    let x = 150.0;
    let y = 1530.0;
    let w = 900.0;
    this.OcPanel(root, x - 20.0, y - 20.0, w + 40.0, 490.0);
    let hd = this.Txt(root, x, y, "FIRE CONTROL   //   MASTER ARM", 30, false);
    hd.SetTintColor(CMPilotHud.Pale());
    let names = ["MORTAR 82", "LMG 7.62 TWIN", "HYDRA 70 PODS"];
    let i = 0;
    while i < 3 {
      let ry = y + 52.0 + Cast<Float>(i) * 112.0;
      let row = this.Frame(root, x - 8.0, ry - 6.0, w + 16.0, 100.0, 1.0);
      CMPilotHud.Bar(row, 3.0, 3.0, w + 10.0, 94.0, this.G(), 0.12);
      ArrayPush(this.m_ocRows, row);
      let arrow = this.Txt(root, x + 4.0, ry + 4.0, ">", 38, false);
      ArrayPush(this.m_ocRowArrows, arrow);
      this.Txt(root, x + 44.0, ry + 4.0, IntToString(i + 1), 38, false).SetOpacity(0.7);
      ArrayPush(this.m_ocRowNames, this.Txt(root, x + 92.0, ry + 2.0, names[i], 38, false));
      let sub = this.Txt(root, x + 92.0, ry + 50.0, "", 26, false);
      sub.SetOpacity(0.8);
      ArrayPush(this.m_ocRowSubs, sub);
      ArrayPush(this.m_ocRowStats, this.OcRight(root, x + w - 10.0, ry + 4.0, "", 32));
      i += 1;
    }
    // the mortar's reload (row 1)
    let r0 = y + 52.0;
    CMPilotHud.Bar(root, x + w - 230.0, r0 + 62.0, 220.0, 12.0, this.G(), 0.2);
    ArrayPush(this.m_ocLoads, CMPilotHud.Bar(root, x + w - 230.0, r0 + 62.0, 220.0, 12.0, this.G(), 0.9));
    // the LMG's heat (row 2)
    let r1 = y + 52.0 + 112.0;
    let p = 0;
    while p < 10 {
      ArrayPush(this.m_ocPips, CMPilotHud.Bar(root, x + w - 330.0 + Cast<Float>(p) * 32.0, r1 + 58.0, 24.0, 20.0, this.G(), 0.25));
      p += 1;
    }
    // the pods' rockets and their reload (row 3)
    let r2 = y + 52.0 + 224.0;
    p = 0;
    while p < 4 {
      ArrayPush(this.m_ocRkPips, CMPilotHud.Bar(root, x + w - 470.0 + Cast<Float>(p) * 34.0, r2 + 56.0, 24.0, 24.0, this.G(), 1.0));
      p += 1;
    }
    CMPilotHud.Bar(root, x + w - 230.0, r2 + 62.0, 220.0, 12.0, this.G(), 0.2);
    ArrayPush(this.m_ocLoads, CMPilotHud.Bar(root, x + w - 230.0, r2 + 62.0, 220.0, 12.0, CMPilotHud.Caution(), 0.9));
    this.Txt(root, x, y + 410.0, "[LMB] FIRE   [B] STATION   [G] ROCKETS   [" + CMKeys.GunshipName(GetPlayer(GetGameInstance())) + "] HOLD   [RMB] ZOOM   [T] SENSOR", 24, false).SetOpacity(0.55);
    // the BDA strip, bottom centre
    this.m_ocBda = this.Txt(root, this.m_W * 0.5, 1990.0, "", 32, true);
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
      // each part's status, left of the schematic
      this.OcPanel(root, x0 - 380.0, y0 - 30.0, W - 140.0 - (x0 - 380.0), 540.0);
      let labels = ["PODS", "LMG", "RKT L", "RKT R", "MORTAR", "SENSOR"];
      let n = 0;
      while n < 6 {
        let ly = y0 + 10.0 + Cast<Float>(n) * 56.0;
        this.Txt(root, x0 - 350.0, ly, labels[n], 28, false).SetOpacity(0.7);
        ArrayPush(this.m_ocParts, this.OcRight(root, x0 - 50.0, ly, "OK", 28));
        n += 1;
      }
      let k = this.SCHEM_H / 560.0;
      let box = new inkCanvas();
      box.SetMargin(inkMargin(x0, y0, 0.0, 0.0));
      box.SetSize(Vector2(537.0 * k, this.SCHEM_H));
      box.Reparent(root);
      // the ten layers of the scan (a34: the body's side tubes, the rear block and the nose cut
      // out as the rocket pods, the mortar and the sensor), in CMUDrone's part order
      this.Part(box, k, n"octant_body", 100.0, 16.0, 335.0, 539.0);
      this.Part(box, k, n"octant_thruster_fl", 5.0, 137.0, 132.0, 138.0);
      this.Part(box, k, n"octant_thruster_fr", 401.0, 137.0, 132.0, 138.0);
      this.Part(box, k, n"octant_thruster_bl", 11.0, 310.0, 126.0, 136.0);
      this.Part(box, k, n"octant_thruster_br", 400.0, 310.0, 127.0, 136.0);
      this.Part(box, k, n"octant_gun", 242.0, 5.0, 53.0, 56.0);
      this.Part(box, k, n"octant_rocket_l", 43.0, 225.0, 81.0, 109.0);
      this.Part(box, k, n"octant_rocket_r", 413.0, 225.0, 81.0, 109.0);
      this.Part(box, k, n"octant_mortar", 206.0, 348.0, 162.0, 202.0);
      this.Part(box, k, n"octant_sensor", 191.0, 15.0, 156.0, 102.0);
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
    this.m_name.SetText(s.title + "  //  GUNSHIP");
    this.m_role.SetText("SNS " + s.sensor + "   " + (s.zoomed ? "NFOV" : "WFOV"));
    this.m_linkT.SetText("LINK C2 " + IntToString(RoundF(s.signal * 100.0)) + "%   RNG " + FloatToStringPrec(s.distance / 1000.0, 2) + " KM");
    this.m_ocAtt.SetText("PITCH " + CMDroneHud.Signed(s.pitch) + "   ROLL " + CMDroneHud.Signed(s.roll));
    this.m_ocClockT.SetText("SPOOL " + IntToString(RoundF(s.spool * 100.0)) + "%   T+ " + CMInk.Clock(this.m_ocClock));
    // the game's day and time
    let gt = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTime();
    let hh = GameTime.Hours(gt);
    let mi = GameTime.Minutes(gt);
    let se = GameTime.Seconds(gt);
    this.m_ocTime.SetText("DAY " + IntToString(GameTime.Days(gt)) + "   " + (hh < 10 ? "0" : "") + IntToString(hh) + ":" + (mi < 10 ? "0" : "") + IntToString(mi) + ":" + (se < 10 ? "0" : "") + IntToString(se));

    this.m_lrf.SetText(s.range > 0.0 && s.range < 2000.0 ? "LRF " + CMPilotHud.Pad4(RoundF(s.range)) + " M" : "LRF ---- M");
    this.m_zoomT.SetText(s.zoomed ? "ZOOM" : "");
    // fire control: the selected station lit
    let i = 0;
    while i < ArraySize(this.m_ocRows) {
      let on = s.weapon == i;
      this.m_ocRows[i].SetOpacity(on ? 1.0 : 0.0);
      this.m_ocRowArrows[i].SetVisible(on);
      this.m_ocRowNames[i].SetTintColor(on ? CMPilotHud.Pale() : this.G());
      let st = i < ArraySize(s.wStat) ? s.wStat[i] : "";
      this.m_ocRowStats[i].SetText(st);
      this.m_ocRowStats[i].SetTintColor(CMDroneHud.StatColor(st));
      this.m_ocRowSubs[i].SetText(i < ArraySize(s.wSub) ? s.wSub[i] : "");
      i += 1;
    }
    let heat = ClampF(s.secHeat, 0.0, 1.0);
    let p = 0;
    while p < ArraySize(this.m_ocPips) {
      let lit = heat * 10.0 > Cast<Float>(p) + 0.05;
      this.m_ocPips[p].SetOpacity(lit ? 1.0 : 0.2);
      this.m_ocPips[p].SetTintColor(heat >= 0.99 ? CMPilotHud.Red() : (lit && p >= 6 ? CMPilotHud.Caution() : this.G()));
      p += 1;
    }
    p = 0;
    while p < ArraySize(this.m_ocRkPips) {
      this.m_ocRkPips[p].SetVisible(p < s.rkMax);
      this.m_ocRkPips[p].SetOpacity(p < s.rkLeft ? 1.0 : 0.2);
      p += 1;
    }
    if ArraySize(this.m_ocLoads) >= 2 {
      this.m_ocLoads[0].SetSize(Vector2(220.0 * ClampF(s.mtLoad, 0.0, 1.0), 12.0));
      this.m_ocLoads[1].SetSize(Vector2(220.0 * ClampF(s.rkLoad, 0.0, 1.0), 12.0));
      this.m_ocLoads[1].SetTintColor(s.rkLoad >= 1.0 ? this.G() : CMPilotHud.Caution());
    }
    this.m_holdT.SetText(s.holdText);
    this.m_windT.SetText(s.windText);
    // each part's status (droneParts: 0 hull, 1-4 pods, 5 LMG, 6-7 rockets, 8 mortar, 9 sensor)
    if ArraySize(this.m_ocParts) >= 6 && ArraySize(s.droneParts) >= 10 {
      let pods = 0;
      let worst = 1.0;
      let k = 1;
      while k <= 4 {
        if s.droneParts[k] > 0.0 {
          pods += 1;
        }
        worst = MinF(worst, s.droneParts[k]);
        k += 1;
      }
      this.m_ocParts[0].SetText(IntToString(pods) + " / 4");
      this.m_ocParts[0].SetTintColor(pods < 4 ? (pods < 3 ? CMPilotHud.Red() : CMPilotHud.Caution()) : CMDroneHud.Health(worst));
      let map = [5, 6, 7, 8, 9];
      let j = 0;
      while j < 5 {
        let hp = s.droneParts[map[j]];
        this.m_ocParts[j + 1].SetText(hp <= 0.0 ? "LOST" : (hp < 0.6 ? "DMG" : "OK"));
        this.m_ocParts[j + 1].SetTintColor(hp <= 0.0 ? CMPilotHud.Red() : CMDroneHud.Health(hp));
        j += 1;
      }
    }
    // hull and parts
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.m_hullT.SetText("HULL " + IntToString(RoundF(hull * 100.0)) + "%");
    this.m_hullBar.SetSize(Vector2(292.0 * hull, 16.0));
    this.m_hullBar.SetTintColor(CMDroneHud.Health(hull));
    i = 0;
    while i < ArraySize(this.m_schemParts) {
      let hp = i < ArraySize(s.droneParts) ? s.droneParts[i] : 1.0;
      let img = this.m_schemParts[i];
      img.SetTintColor(hp <= 0.0 ? CMPilotHud.Grey() : CMDroneHud.Health(hp));
      img.SetOpacity(hp <= 0.0 ? 0.45 : 1.0);
      i += 1;
    }
    this.m_warnT.SetText(s.warning);
  }

  // a station's status colour: ready green, waiting amber, lost red
  public static func StatColor(st: String) -> HDRColor {
    if Equals(st, "LOST") || Equals(st, "OVERHEAT") {
      return CMPilotHud.Red();
    }
    if StrBeginsWith(st, "RLD") || Equals(st, "OFF ARC") || Equals(st, "NO SOLN") {
      return CMPilotHud.Caution();
    }
    return CMPilotHud.Amber();
  }

  // every frame from the drone: what its sensor sees (CMDroneSense). Here the sensor block's
  // target lines, the map and the BDA; the other drones' displays draw their own.
  public func Track(t: ref<CMDroneTrack>) -> Void {
    if !IsDefined(this.m_droot) || !IsDefined(this.m_ocMap) {
      return;
    }
    this.m_ocLase.SetVisible(t.aimOk);
    if t.aimOk {
      this.m_ocTgt.SetText("TGT  X " + FloatToStringPrec(t.aim.X, 1) + "   Y " + FloatToStringPrec(t.aim.Y, 1) + "   Z " + FloatToStringPrec(t.aim.Z, 1));
      let fx = t.aim.X - t.pos.X;
      let fy = t.aim.Y - t.pos.Y;
      let flat = SqrtF(fx * fx + fy * fy);
      this.m_ocLrf.SetText("LRF " + CMPilotHud.Pad4(RoundF(flat)) + " M   SLANT " + CMPilotHud.Pad4(RoundF(Vector4.Distance(t.pos, t.aim))) + " M   EL " + CMDroneHud.Signed(t.camPitch));
    } else {
      this.m_ocTgt.SetText("TGT  ----");
      this.m_ocLrf.SetText("LRF ----   SLANT ----   EL " + CMDroneHud.Signed(t.camPitch));
    }
    this.m_ocAz.SetText("SNS AZ " + CMPilotHud.Pad3(CMInk.Hdg(-t.yaw)) + "   EL " + CMDroneHud.Signed(t.camPitch) + "   SLAVED");
    // the map: north up, the drone in the middle
    let c = this.OC_MAP * 0.5;
    let lim = c - 10.0;
    let k = this.OC_MPX;
    this.m_ocSelf.SetRotation(-t.yaw);
    if t.aimOk {
      let ax = (t.aim.X - t.pos.X) * k;
      let ay = -(t.aim.Y - t.pos.Y) * k;
      let len = SqrtF(ax * ax + ay * ay);
      if len > lim {
        ax *= lim / len;
        ay *= lim / len;
      }
      CMInk.Seg(this.m_ocSight, c, c, c + ax, c + ay, 3.0);
      this.m_ocSight.SetVisible(len > 2.0);
      this.m_ocAimX.SetVisible(true);
      this.m_ocAimX.SetMargin(inkMargin(c + ax - 14.0, c + ay - 14.0, 0.0, 0.0));
    } else {
      this.m_ocSight.SetVisible(false);
      this.m_ocAimX.SetVisible(false);
    }
    if t.hold {
      let hx = (t.holdAt.X - t.pos.X) * k;
      let hy = -(t.holdAt.Y - t.pos.Y) * k;
      this.m_ocStation.SetVisible(AbsF(hx) < lim && AbsF(hy) < lim);
      this.m_ocStation.SetMargin(inkMargin(c + hx - 20.0, c + hy - 20.0, 0.0, 0.0));
    } else {
      this.m_ocStation.SetVisible(false);
    }
    let i = 0;
    let n = Min(ArraySize(t.contacts), ArraySize(this.m_ocDots));
    while i < n {
      let ct = t.contacts[i];
      let dx = (ct.pos.X - t.pos.X) * k;
      let dy = -(ct.pos.Y - t.pos.Y) * k;
      let d = this.m_ocDots[i];
      let show = AbsF(dx) < lim && AbsF(dy) < lim;
      d.SetVisible(show);
      if show {
        let sz = ct.kind == 0 ? 20.0 : 14.0;
        d.SetSize(Vector2(sz, sz));
        d.SetMargin(inkMargin(c + dx - sz * 0.5, c + dy - sz * 0.5, 0.0, 0.0));
        d.SetTintColor(CMDroneHud.MapColor(ct.kind));
        d.SetRotation(ct.kind == 0 ? 45.0 : 0.0);
        d.SetRenderTransformPivot(Vector2(0.5, 0.5));
      }
      i += 1;
    }
    while i < ArraySize(this.m_ocDots) {
      this.m_ocDots[i].SetVisible(false);
      i += 1;
    }
    this.m_ocMapT.SetText("MAP 120 M   //   " + (t.hold ? "STATION HOLD" : "FREE FLIGHT") + "   //   HOSTILES " + IntToString(t.hostiles));
    // the BDA
    let acc = t.rounds > 0 ? RoundF(Cast<Float>(t.hits) * 100.0 / Cast<Float>(t.rounds)) : 0;
    this.m_ocBda.SetText("BDA   KIA " + IntToString(this.m_ocKills) + "   //   RDS " + IntToString(t.rounds) + "   HITS " + IntToString(t.hits) + "   ACC " + IntToString(acc) + "%");
  }

  public static func MapColor(kind: Int32) -> HDRColor {
    switch kind {
      case 0: return new HDRColor(0.45, 0.85, 1.15, 1.0);
      case 1: return CMPilotHud.Grey();
      case 2: return CMPilotHud.Red();
      case 4: return CMPilotHud.Amber();
    }
    return CMPilotHud.Pale();
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
    if IsDefined(this.m_droot) {
      this.m_ocClock += dt;
    }
    // a threat's bearing: on the tape while it is in view, 3 s
    if IsDefined(this.m_ocThreat) {
      if this.m_ocThreatT > 0.0 {
        this.m_ocThreatT -= dt;
        let rel = this.m_ocThreatB - this.m_ocHeading;
        while rel > 180.0 { rel -= 360.0; }
        while rel < -180.0 { rel += 360.0; }
        let x = this.m_W * 0.5 + rel * this.HDG_PX;
        this.m_ocThreatTick.SetVisible(this.m_ocThreatT > 0.0 && AbsF(rel * this.HDG_PX) <= 600.0);
        this.m_ocThreatTick.SetMargin(inkMargin(x - 4.0, 156.0, 0.0, 0.0));
        this.m_ocThreat.SetText(this.m_ocThreatT > 0.0 ? "THREAT  " + CMPilotHud.Pad3(CMInk.Hdg(this.m_ocThreatB)) : "");
        let ph = this.m_ocThreatT * 2.0;
        this.m_ocThreat.SetOpacity(ph - Cast<Float>(FloorF(ph)) < 0.6 ? 1.0 : 0.4);
      } else {
        this.m_ocThreatTick.SetVisible(false);
        this.m_ocThreat.SetText("");
      }
    }
  }

  public func Tags(dt: Float) -> Void {}
  public func TagFlash(i: Int32) -> Void {}
  public func SetOptics(on: Bool) -> Void {}

  // the drone was shot from `off` degrees off the view (the session's yaw: + left): its
  // bearing for 3 s
  public func HitFrom(off: Float) -> Void {
    this.m_ocThreatT = 3.0;
    this.m_ocThreatB = this.m_ocHeading - off;
  }

  // a hit the drone's weapons scored: the crosshair flashes amber; a kill counts on the BDA
  public func Hit(kill: Bool) -> Void {
    this.m_flashT = kill ? 0.5 : 0.15;
    if kill {
      this.m_ocKills += 1;
    }
  }

  public func PartHit(i: Int32) -> Void {}
  public func Damage(lost: Float) -> Void {}
}
