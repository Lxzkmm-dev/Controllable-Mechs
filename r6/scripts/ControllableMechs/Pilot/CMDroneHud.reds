// =============================================================================
// MECHS OF NIGHT CITY - DRONE HUD: THE OCTANT'S GUNSHIP DISPLAY (0.7.1-a50)
//
// A drone's own display, after an MQ-1 sensor operator's, laid out as Omar's gunship
// mockup (octant_gunship_hud_mockup): one phosphor green, thin-bordered dark panels with
// small headers and table rows, amber for the gunship's state, red for threats. On the
// 2160-high design space of the mech HUD (CMPilotHud, whose small drawing helpers it uses):
//   top left     the sensor ball: the airframe; MTS mode and field of view; the link (C-band,
//                its strength as a bar, the range to V); the laser (ARMED while it has a
//                return) and autotrack (ON while a contact is locked); REC and the game's
//                day and time, the flight's clock
//   top centre   the heading tape with the heading boxed; the gunship banner under it
//                while holding (its standoff from the target); a threat's bearing
//   top right    the target block: slant range, bearing, height difference, the locked
//                target's speed (STATIC / MOVING / NO LASE)
//   centre       the MTS crosshair (thin arms with ticks, a bracket box, no horizon line);
//                the laser range, the L cue and LASING; the look-down angle (DEP) on an arc;
//                the mortar's spread, a dashed ellipse on the ground where the salvo will
//                land, its leader line to MORTAR x4 SPREAD and the time of flight
//   left / right speed (m/s) and altitude (m above the ground) tapes, values boxed, VS
//   left         the situation map: north up round the drone, 100 m; the sensor's footprint
//                filled on the ground, the target (TGT), the orbit at the standoff round it
//                dashed, V, every contact the sweep found (CMDroneSense)
//   bottom left  the stores page: a row per station (STA1 mortar, STA2 LMG x2, STA3
//                rockets), the selected one filled, MASTER ARM, the keys
//   bottom right the airframe: the damage schematic (a layer per part coloured by its
//                health, greyed when destroyed), the hull and the thrusters left
//   bottom       the BDA: kills, rounds, hits
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
  private let m_lrf: ref<inkText>;
  private let m_name: ref<inkText>;
  private let m_cross: ref<inkCanvas>;
  private let m_holdT: ref<inkText>;
  private let m_holdBox: ref<inkCanvas>;
  private let m_windT: ref<inkText>;
  private let m_hullT: ref<inkText>;
  private let m_warnT: ref<inkText>;
  private let m_impact: ref<inkCanvas>;
  private let m_schemParts: array<ref<inkWidget>>;
  private let m_schemNames: array<CName>;
  private let m_flashT: Float;
  // the sensor block
  private let m_ocMts: ref<inkText>;
  private let m_ocSensor: String;
  private let m_ocZoomed: Bool;
  private let m_ocLink: ref<CMSlider>;
  private let m_ocLinkPct: ref<inkText>;
  private let m_ocLinkRng: ref<inkText>;
  private let m_ocLaser: ref<inkText>;
  private let m_ocTrack: ref<inkText>;
  private let m_ocRecDot: ref<inkImage>;
  private let m_ocTime: ref<inkText>;
  private let m_ocClock: Float;
  // the target block
  private let m_ocTgtTag: ref<inkText>;
  private let m_ocSlant: ref<inkText>;
  private let m_ocBrg: ref<inkText>;
  private let m_ocDh: ref<inkText>;
  private let m_ocSpd: ref<inkText>;
  // the centre
  private let m_ocLcue: ref<inkCanvas>;
  private let m_ocLasing: ref<inkText>;
  private let m_ocDepNeedle: ref<inkImage>;
  private let m_ocDepT: ref<inkText>;
  private let m_ocSplash: array<ref<inkImage>>;
  private let m_ocLeader: array<ref<inkImage>>;
  private let m_ocSplashT: ref<inkText>;
  private let m_ocSplashT2: ref<inkText>;
  // the map
  private let m_ocMap: ref<inkCanvas>;
  private let m_ocDots: array<ref<inkImage>>;
  private let m_ocSelf: ref<inkCanvas>;
  private let m_ocFoot: array<ref<inkRectangle>>;
  private let m_ocFootEdge: array<ref<inkImage>>;
  private let m_ocOrbit: array<ref<inkImage>>;
  private let m_ocTgtMark: ref<inkCanvas>;
  private let m_ocTgtLbl: ref<inkText>;
  private let m_ocV: ref<inkImage>;
  private let m_ocVLbl: ref<inkText>;
  // the stores page
  private let m_ocRows: array<ref<inkImage>>;
  private let m_ocRowSta: array<ref<inkText>>;
  private let m_ocRowNames: array<ref<inkText>>;
  private let m_ocRowSubs: array<ref<inkText>>;
  private let m_ocRowStats: array<ref<inkText>>;
  private let m_ocArm: ref<inkText>;
  // the airframe, the BDA, threats
  private let m_ocThr: ref<inkText>;
  private let m_ocBda: ref<inkText>;
  private let m_ocKills: Int32;
  private let m_ocThreat: ref<inkText>;
  private let m_ocThreatTick: ref<inkRectangle>;
  private let m_ocThreatT: Float;
  private let m_ocThreatB: Float;
  private let m_ocHeading: Float;

  private let HDG_PX: Float = 6.0;       // px per degree on the heading tape
  private let SCHEM_H: Float = 430.0;    // the damage schematic's height on screen
  private let OC_MAP_R: Float = 200.0;   // the map's radius on screen (100 m)
  private let OC_MPX: Float = 2.0;       // its px per m
  private let OC_DEP_R: Float = 150.0;   // the look-down arc's radius

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
    this.BuildHeading(root);
    this.BuildTapes(root);
    this.BuildCentre(root);
    this.BuildSensor(root);
    this.BuildTarget(root);
    this.BuildMap(root);
    this.BuildStores(root);
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
    ArrayClear(this.m_ocDots);
    ArrayClear(this.m_ocRows);
    ArrayClear(this.m_ocRowSta);
    ArrayClear(this.m_ocRowNames);
    ArrayClear(this.m_ocRowSubs);
    ArrayClear(this.m_ocRowStats);
    ArrayClear(this.m_ocSplash);
    ArrayClear(this.m_ocLeader);
    ArrayClear(this.m_ocFoot);
    ArrayClear(this.m_ocFootEdge);
    ArrayClear(this.m_ocOrbit);
  }

  // ---- drawing -----------------------------------------------------------------
  private func G() -> HDRColor = CMPilotHud.Amber()
  private func Lbl() -> HDRColor = new HDRColor(0.22, 0.70, 0.32, 1.0)    // a table's labels
  private func Hi() -> HDRColor = new HDRColor(0.82, 1.05, 0.86, 1.0)     // titles, values
  private func Line(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, op: Float) -> ref<inkRectangle> = CMPilotHud.Bar(root, x, y, w, h, this.G(), op)
  private func Txt(root: ref<inkCanvas>, x: Float, y: Float, text: String, size: Int32, centred: Bool) -> ref<inkText> {
    let t = CMPilotHud.Label(root, inkEAnchor.TopLeft, x, y, text, size, n"Medium", this.G());
    if centred {
      t.SetAnchorPoint(Vector2(0.5, 0.0));
    }
    return t;
  }
  private func TxtC(root: ref<inkCanvas>, x: Float, y: Float, text: String, size: Int32, c: HDRColor) -> ref<inkText> {
    let t = CMPilotHud.Label(root, inkEAnchor.TopLeft, x, y, text, size, n"Medium", c);
    return t;
  }
  private func OcRight(root: ref<inkCanvas>, x: Float, y: Float, text: String, size: Int32, c: HDRColor) -> ref<inkText> {
    let t = this.TxtC(root, x, y, text, size, c);
    t.SetAnchorPoint(Vector2(1.0, 0.0));
    return t;
  }
  // an outlined box
  private func Frame(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, op: Float) -> ref<inkCanvas> {
    let c = new inkCanvas();
    c.SetMargin(inkMargin(x, y, 0.0, 0.0));
    c.SetSize(Vector2(w, h));
    c.Reparent(root);
    this.Line(c, 0.0, 0.0, w, 2.0, op);
    this.Line(c, 0.0, h - 2.0, w, 2.0, op);
    this.Line(c, 0.0, 0.0, 2.0, h, op);
    this.Line(c, w - 2.0, 0.0, 2.0, h, op);
    return c;
  }
  // a panel: dark glass inside a thin border (the mockup's)
  private func OcPanel(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float) -> Void {
    CMKit.Panel(root, x, y, w, h, this.G(), 0.75);
  }

  // ---- the heading tape: a tick every 5 deg (long every 10), a label every 10 -----------
  private func BuildHeading(root: ref<inkCanvas>) -> Void {
    let cx = this.m_W * 0.5;
    this.Line(root, cx - 600.0, 166.0, 1200.0, 2.0, 0.9);
    let i = 0;
    while i < 41 {
      ArrayPush(this.m_hdgTicks, this.Line(root, cx, 146.0, 2.0, 20.0, 0.9));
      i += 1;
    }
    i = 0;
    while i < 13 {
      ArrayPush(this.m_hdgLabels, this.Txt(root, cx, 176.0, "00", 26, true));
      i += 1;
    }
    CMKit.Box(root, cx - 85.0, 52.0, 170.0, 64.0, this.G(), 1.0);
    this.m_hdgBox = this.Txt(root, cx, 60.0, "000", 44, true);
    this.m_hdgBox.SetTintColor(this.Hi());
    this.Line(root, cx - 1.0, 116.0, 2.0, 30.0, 1.0);
    // the gunship banner (shown while holding)
    let hb = new inkCanvas();
    hb.SetMargin(inkMargin(cx - 420.0, 226.0, 0.0, 0.0));
    hb.SetSize(Vector2(840.0, 52.0));
    hb.Reparent(root);
    CMKit.Box(hb, 0.0, 0.0, 840.0, 52.0, CMPilotHud.Caution(), 1.0);
    this.m_holdBox = hb;
    this.m_holdT = this.Txt(root, cx, 234.0, "", 28, true);
    this.m_holdT.SetTintColor(CMPilotHud.Caution());
    this.m_holdBox.SetVisible(false);
    // a threat's bearing: a red tick on the tape and its line beside it
    this.m_ocThreatTick = CMPilotHud.Bar(root, cx, 136.0, 8.0, 40.0, CMPilotHud.Red(), 1.0);
    this.m_ocThreatTick.SetVisible(false);
    this.m_ocThreat = this.Txt(root, cx + 640.0, 140.0, "", 32, false);
    this.m_ocThreat.SetTintColor(CMPilotHud.Red());
    this.m_warnT = this.Txt(root, cx, 300.0, "", 36, true);
    this.m_warnT.SetTintColor(CMPilotHud.Red());
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
      t.SetMargin(inkMargin(x - 1.0, long ? 142.0 : 152.0, 0.0, 0.0));
      t.SetSize(Vector2(2.0, long ? 24.0 : 14.0));
      i += 1;
    }
    // a label every 10 degrees: two digits, the cardinals as letters (the mockup's)
    let lbase = FloorF(h / 10.0) * 10;
    i = 0;
    while i < ArraySize(this.m_hdgLabels) {
      let deg = lbase + (i - 6) * 10;
      let x = cx + (Cast<Float>(deg) - h) * this.HDG_PX;
      let l = this.m_hdgLabels[i];
      l.SetVisible(AbsF(x - cx) <= 590.0);
      l.SetMargin(inkMargin(x, 176.0, 0.0, 0.0));
      let d = deg % 360;
      if d < 0 {
        d += 360;
      }
      let s = d / 10;
      l.SetText(d == 0 ? "N" : (d == 90 ? "E" : (d == 180 ? "S" : (d == 270 ? "W" : (s < 10 ? "0" : "") + IntToString(s)))));
      i += 1;
    }
    this.m_hdgBox.SetText(CMPilotHud.Pad3(RoundF(h) % 360));
  }

  // ---- speed and altitude: a ladder with a boxed value at the middle -----------------
  private func BuildTapes(root: ref<inkCanvas>) -> Void {
    let cx = this.m_W * 0.5;
    let xl = cx - 1050.0;
    let xr = cx + 1050.0;
    this.Line(root, xl, 600.0, 2.0, 960.0, 0.8);
    this.Line(root, xr, 600.0, 2.0, 960.0, 0.8);
    let y = 600.0;
    let n = 0;
    while y <= 1560.0 {
      let long = n % 2 == 0;
      this.Line(root, xl, y, long ? 30.0 : 18.0, 2.0, 0.8);
      this.Line(root, xr - (long ? 28.0 : 16.0), y, long ? 30.0 : 18.0, 2.0, 0.8);
      y += 80.0;
      n += 1;
    }
    this.Txt(root, xl + 20.0, 548.0, "M/S", 26, true);
    this.Txt(root, xr - 20.0, 548.0, "ALT M", 26, true);
    CMKit.Box(root, xl - 210.0, 1050.0, 190.0, 62.0, this.G(), 1.0);
    CMKit.Box(root, xr + 20.0, 1050.0, 190.0, 62.0, this.G(), 1.0);
    this.m_speedText = this.Txt(root, xl - 115.0, 1054.0, "0.0", 44, true);
    this.m_altText = this.Txt(root, xr + 115.0, 1054.0, "000", 44, true);
    this.m_speedText.SetTintColor(this.Hi());
    this.m_altText.SetTintColor(this.Hi());
    this.m_vsText = this.Txt(root, xr + 115.0, 1124.0, "VS 0.0", 26, true);
  }

  // ---- the centre: the MTS crosshair, the laser, the look-down arc, the mortar's spread ----
  private func BuildCentre(root: ref<inkCanvas>) -> Void {
    let cx = this.m_W * 0.5;
    let cy = 1080.0;
    let c = new inkCanvas();
    c.SetMargin(inkMargin(cx - 260.0, cy - 160.0, 0.0, 0.0));
    c.SetSize(Vector2(520.0, 320.0));
    c.Reparent(root);
    this.m_cross = c;
    // the arms: long and thin, a tick every 33 px; gapped round a bracket box
    let ox = 260.0;
    let oy = 160.0;
    this.Line(c, ox - 250.0, oy - 1.0, 215.0, 2.0, 0.9);
    this.Line(c, ox + 35.0, oy - 1.0, 215.0, 2.0, 0.9);
    this.Line(c, ox - 1.0, oy - 150.0, 2.0, 115.0, 0.9);
    this.Line(c, ox - 1.0, oy + 35.0, 2.0, 115.0, 0.9);
    let k = 1;
    while k <= 6 {
      let d = 35.0 + Cast<Float>(k) * 33.0;
      this.Line(c, ox - d, oy - 8.0, 2.0, 16.0, 0.8);
      this.Line(c, ox + d - 2.0, oy - 8.0, 2.0, 16.0, 0.8);
      if k <= 3 {
        this.Line(c, ox - 8.0, oy - d, 16.0, 2.0, 0.8);
        this.Line(c, ox - 8.0, oy + d - 2.0, 16.0, 2.0, 0.8);
      }
      k += 1;
    }
    let b = 20.0;
    let L = 10.0;
    this.Line(c, ox - b, oy - b, L, 3.0, 1.0);
    this.Line(c, ox - b, oy - b, 3.0, L, 1.0);
    this.Line(c, ox + b - L, oy - b, L, 3.0, 1.0);
    this.Line(c, ox + b - 3.0, oy - b, 3.0, L, 1.0);
    this.Line(c, ox - b, oy + b - 3.0, L, 3.0, 1.0);
    this.Line(c, ox - b, oy + b - L, 3.0, L, 1.0);
    this.Line(c, ox + b - L, oy + b - 3.0, L, 3.0, 1.0);
    this.Line(c, ox + b - 3.0, oy + b - L, 3.0, L, 1.0);
    CMKit.Disc(c, ox, oy, 4.0, this.G(), 1.0);
    // the laser range, the L cue and LASING
    this.m_lrf = this.Txt(root, cx - 20.0, cy + 330.0, "LRF ---- M", 36, false);
    this.m_lrf.SetAnchorPoint(Vector2(1.0, 0.0));
    let l = new inkCanvas();
    l.SetMargin(inkMargin(cx + 10.0, cy + 330.0, 0.0, 0.0));
    l.SetSize(Vector2(40.0, 40.0));
    l.Reparent(root);
    CMKit.Fill(l, 0.0, 0.0, 40.0, 40.0, CMPilotHud.Caution(), 1.0);
    let lt = CMPilotHud.Label(l, inkEAnchor.TopLeft, 20.0, 2.0, "L", 30, n"Semi-Bold", CMPilotHud.Black());
    lt.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_ocLcue = l;
    this.m_ocLasing = this.TxtC(root, cx + 64.0, cy + 336.0, "LASING", 28, CMPilotHud.Caution());
    // the look-down angle: a quarter arc (level at its left, straight down at its foot), a
    // tick every 10 degrees, its needle
    let ax = cx + 560.0;
    let ay = cy - 250.0;
    let r = this.OC_DEP_R;
    let ring = CMInk.Ring(root, ax, ay, r, 72, 3.0, this.G(), 0.9);
    let q = 0;
    while q < 72 {
      let a = Cast<Float>(q) * 5.0;
      ring[q].SetVisible(a >= 180.0 && a <= 270.0);
      q += 1;
    }
    let tk = 0;
    while tk <= 9 {
      let a = Deg2Rad(270.0 - Cast<Float>(tk) * 10.0);
      CMInk.Line(root, ax + SinF(a) * r, ay - CosF(a) * r, ax + SinF(a) * (r - 18.0), ay - CosF(a) * (r - 18.0), 2.0, this.G(), 0.8);
      tk += 1;
    }
    this.m_ocDepNeedle = CMKit.Stroke(root, CMPilotHud.Caution(), 1.0);
    this.m_ocDepT = this.TxtC(root, ax - r - 30.0, ay - 50.0, "DEP 00", 30, this.Hi());
    // the mortar's predicted impact (kept for its callers; the spread below shows it)
    let im = new inkCanvas();
    im.SetSize(Vector2(10.0, 10.0));
    im.SetVisible(false);
    im.Reparent(root);
    this.m_impact = im;
    // the mortar's spread: a dashed amber ellipse on the ground, a leader to its words
    let a2 = CMPilotHud.Caution();
    let n = 0;
    while n < 32 {
      let s = CMKit.Stroke(root, a2, 1.0);
      s.SetVisible(false);
      ArrayPush(this.m_ocSplash, s);
      n += 1;
    }
    n = 0;
    while n < 2 {
      let s = CMKit.Stroke(root, a2, 0.9);
      s.SetVisible(false);
      ArrayPush(this.m_ocLeader, s);
      n += 1;
    }
    this.m_ocSplashT = this.TxtC(root, 0.0, 0.0, "", 30, a2);
    this.m_ocSplashT2 = this.TxtC(root, 0.0, 0.0, "", 28, a2);
    this.m_ocSplashT.SetVisible(false);
    this.m_ocSplashT2.SetVisible(false);
  }

  // the mortar's predicted impact: drawn as the spread on the ground (Track)
  public func SetImpact(on: Bool, x: Float, y: Float, tof: Float) -> Void {}

  // ---- the sensor block, top left ----------------------------------------------------
  private func BuildSensor(root: ref<inkCanvas>) -> Void {
    let x = 60.0;
    let y = 90.0;   // (a52: clear of the top edge on Omar's ultrawide)
    this.OcPanel(root, x, y, 820.0, 250.0);
    this.m_name = this.TxtC(root, x + 22.0, y + 10.0, "DRONE", 40, this.Hi());
    let r1 = y + 70.0;
    let r2 = y + 112.0;
    let r3 = y + 154.0;
    let r4 = y + 196.0;
    this.TxtC(root, x + 22.0, r1, "MTS", 28, this.Lbl());
    this.m_ocMts = this.TxtC(root, x + 130.0, r1, "", 28, this.G());
    this.TxtC(root, x + 22.0, r2, "LINK", 28, this.Lbl());
    this.TxtC(root, x + 130.0, r2, "C-BAND", 28, this.G());
    this.m_ocLink = CMSlider.Make(root, x + 300.0, r2 + 10.0, 200.0, 16.0, false, this.G());
    this.m_ocLinkPct = this.TxtC(root, x + 520.0, r2, "", 28, this.Hi());
    this.m_ocLinkRng = this.TxtC(root, x + 640.0, r2, "", 28, this.Hi());
    this.TxtC(root, x + 22.0, r3, "LASER", 28, this.Lbl());
    this.m_ocLaser = this.TxtC(root, x + 130.0, r3, "", 28, CMPilotHud.Caution());
    this.TxtC(root, x + 300.0, r3, "AUTOTRACK", 28, this.Lbl());
    this.m_ocTrack = this.TxtC(root, x + 470.0, r3, "", 28, this.G());
    this.TxtC(root, x + 22.0, r4, "REC", 28, this.Hi());
    this.m_ocRecDot = CMKit.Disc(root, x + 99.0, r4 + 17.0, 9.0, CMPilotHud.Red(), 1.0);
    this.m_ocTime = this.TxtC(root, x + 130.0, r4, "", 28, this.Hi());
  }

  // ---- the target block, top right --------------------------------------------------
  private func BuildTarget(root: ref<inkCanvas>) -> Void {
    let x = this.m_W - 60.0 - 680.0;
    let y = 90.0;
    this.OcPanel(root, x, y, 680.0, 250.0);
    this.TxtC(root, x + 22.0, y + 10.0, "TARGET", 36, this.Hi());
    this.m_ocTgtTag = this.OcRight(root, x + 660.0, y + 14.0, "", 28, CMPilotHud.Caution());
    let rows = ["SLANT", "BRG", "DH", "TGT SPD"];
    let i = 0;
    while i < 4 {
      let ry = y + 70.0 + Cast<Float>(i) * 42.0;
      this.TxtC(root, x + 22.0, ry, rows[i], 28, this.Lbl());
      let v = this.TxtC(root, x + 220.0, ry, "", 28, this.Hi());
      switch i {
        case 0: this.m_ocSlant = v; break;
        case 1: this.m_ocBrg = v; break;
        case 2: this.m_ocDh = v; break;
        default: this.m_ocSpd = v; break;
      }
      i += 1;
    }
    this.m_windT = this.OcRight(root, this.m_W - 60.0, y + 262.0, "", 26, this.G());
    this.m_windT.SetOpacity(0.75);
  }

  // ---- the situation map, left ------------------------------------------------------
  private func BuildMap(root: ref<inkCanvas>) -> Void {
    let x = 40.0;
    let y = 1080.0;
    let w = 650.0;
    let h = 500.0;
    this.OcPanel(root, x, y, w, h);
    this.TxtC(root, x + 18.0, y + 10.0, "SITUATION", 26, this.Lbl());
    this.OcRight(root, x + w - 18.0, y + 10.0, "N UP   100 M", 26, this.Lbl());
    let m = new inkCanvas();
    m.SetMargin(inkMargin(x + w * 0.5 - this.OC_MAP_R, y + 60.0 + 10.0, 0.0, 0.0));
    m.SetSize(Vector2(this.OC_MAP_R * 2.0, this.OC_MAP_R * 2.0));
    m.Reparent(root);
    this.m_ocMap = m;
    let c = this.OC_MAP_R;
    CMInk.Circle(m, c, c, this.OC_MAP_R, this.G(), 0.7);
    CMInk.Circle(m, c, c, this.OC_MAP_R * 0.5, this.G(), 0.4);
    this.Line(m, c - 1.0, 0.0, 2.0, c * 2.0, 0.15);
    this.Line(m, 0.0, c - 1.0, c * 2.0, 2.0, 0.15);
    // the sensor's footprint, filled
    // (a52: fine strips and its two edges drawn over them: 24 strips read as stairs)
    this.m_ocFoot = CMInk.FillBars(m, 110, this.G(), 0.32);
    let fe = 0;
    while fe < 3 {
      let b = CMKit.Stroke(m, this.G(), 0.95);
      b.SetVisible(false);
      ArrayPush(this.m_ocFootEdge, b);
      fe += 1;
    }
    // the orbit round the target at the standoff: dashed amber
    let n = 0;
    while n < 32 {
      let s = CMKit.Stroke(m, CMPilotHud.Caution(), 1.0);
      s.SetVisible(false);
      ArrayPush(this.m_ocOrbit, s);
      n += 1;
    }
    // the contacts
    let i = 0;
    while i < 32 {
      let d = CMKit.Disc(m, 0.0, 0.0, 7.0, this.G(), 1.0);
      d.SetVisible(false);
      d.SetRenderTransformPivot(Vector2(0.5, 0.5));
      ArrayPush(this.m_ocDots, d);
      i += 1;
    }
    // V: a light-blue dot and its letter
    this.m_ocV = CMKit.Disc(m, 0.0, 0.0, 8.0, new HDRColor(0.45, 0.85, 1.15, 1.0), 1.0);
    this.m_ocVLbl = this.TxtC(m, 0.0, 0.0, "V", 24, new HDRColor(0.45, 0.85, 1.15, 1.0));
    // the target: a red diamond, TGT beside it
    let tg = new inkCanvas();
    tg.SetSize(Vector2(24.0, 24.0));
    tg.SetRenderTransformPivot(Vector2(0.5, 0.5));
    tg.Reparent(m);
    CMKit.Img(tg, n"diamond", 0.0, 0.0, 24.0, 24.0, CMPilotHud.Red(), 1.0);
    this.m_ocTgtMark = tg;
    this.m_ocTgtLbl = this.TxtC(m, 0.0, 0.0, "TGT", 24, CMPilotHud.Red());
    // the drone: a white triangle (a chevron) in the middle, pointing where it looks
    this.m_ocSelf = CMInk.Chevron(m, 34.0, 6.0, this.Hi());
    this.m_ocSelf.SetMargin(inkMargin(c - 17.0, c - 17.0, 0.0, 0.0));
  }

  // ---- the stores page, bottom left -------------------------------------------------
  private func BuildStores(root: ref<inkCanvas>) -> Void {
    let x = 40.0;
    let y = 1600.0;
    let w = 650.0;
    this.OcPanel(root, x, y, w, 390.0);
    this.TxtC(root, x + 18.0, y + 10.0, "STORES", 26, this.Lbl());
    this.m_ocArm = this.OcRight(root, x + w - 18.0, y + 10.0, "MASTER ARM ON", 26, CMPilotHud.Caution());
    let names = ["MORTAR", "LMG X2", "ROCKETS"];
    let i = 0;
    while i < 3 {
      let ry = y + 56.0 + Cast<Float>(i) * 92.0;
      let row = CMKit.Fill(root, x + 8.0, ry, w - 16.0, 80.0, this.G(), 0.85);
      ArrayPush(this.m_ocRows, row);
      ArrayPush(this.m_ocRowSta, this.TxtC(root, x + 22.0, ry + 22.0, "STA" + IntToString(i + 1), 26, this.Lbl()));
      ArrayPush(this.m_ocRowNames, this.TxtC(root, x + 110.0, ry + 14.0, names[i], 38, this.Hi()));
      ArrayPush(this.m_ocRowSubs, this.TxtC(root, x + 300.0, ry + 22.0, "", 26, this.G()));
      ArrayPush(this.m_ocRowStats, this.OcRight(root, x + w - 24.0, ry + 20.0, "", 28, this.G()));
      i += 1;
    }
    this.TxtC(root, x + 18.0, y + 350.0, "[B] STA   [LMB] FIRE   [G] MISSILE   [" + CMKeys.GunshipName(GetPlayer(GetGameInstance())) + "] HOLD   [RMB] ZOOM   [T] SENSOR", 22, this.Lbl());
    // the BDA, bottom centre
    this.m_ocBda = this.Txt(root, this.m_W * 0.5, 1990.0, "", 28, true);
    this.m_ocBda.SetOpacity(0.8);
  }

  // ---- the airframe, bottom right: the damage schematic, its parts from the atlas
  // (tools/drones/schematic.py: each part's place in the whole, in its 537 x 560 composite)
  private func BuildDamage(root: ref<inkCanvas>) -> Void {
    let W = this.m_W;
    let pw = 500.0;
    let px = W - 40.0 - pw;
    let py = 1480.0;
    this.OcPanel(root, px, py, pw, 510.0);
    this.TxtC(root, px + 18.0, py + 10.0, "AIRFRAME", 26, this.Lbl());
    let k = 380.0 / 560.0;
    let x0 = px + (pw - 537.0 * k) * 0.5;
    let y0 = py + 56.0;
    if Equals(this.m_kind, "octant") {
      let box = new inkCanvas();
      box.SetMargin(inkMargin(x0, y0, 0.0, 0.0));
      box.SetSize(Vector2(537.0 * k, 380.0));
      box.Reparent(root);
      // the ten layers of the scan, in CMUDrone's part order
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
    this.m_hullT = this.TxtC(root, px + 22.0, py + 456.0, "HULL 100%", 30, this.Hi());
    this.m_ocThr = this.TxtC(root, px + 260.0, py + 456.0, "THR 4/4", 30, this.Hi());
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

  // ---- ten times a second ------------------------------------------------------------
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.m_droot) {
      return;
    }
    this.m_name.SetText(s.title + "  //  GUNSHIP");
    let sig = ClampF(s.signal, 0.0, 1.0);
    this.m_ocLink.Set(sig, sig < 0.35 ? CMPilotHud.Red() : this.G());
    this.m_ocLinkPct.SetText(IntToString(RoundF(sig * 100.0)) + "%");
    this.m_ocLinkRng.SetText(FloatToStringPrec(s.distance / 1000.0, 2) + "KM");
    // the game's day and time, and the flight's clock
    let gt = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTime();
    let hh = GameTime.Hours(gt);
    let mi = GameTime.Minutes(gt);
    let se = GameTime.Seconds(gt);
    this.m_ocTime.SetText("DAY " + IntToString(GameTime.Days(gt)) + "  " + (hh < 10 ? "0" : "") + IntToString(hh) + ":" + (mi < 10 ? "0" : "") + IntToString(mi) + ":" + (se < 10 ? "0" : "") + IntToString(se) + "   T+ " + CMInk.Clock(this.m_ocClock));
    this.m_lrf.SetText(s.range > 0.0 && s.range < 2000.0 ? "LRF " + CMPilotHud.Pad4(RoundF(s.range)) + " M" : "LRF ---- M");
    // the stores page: the selected station filled, its words dark
    let i = 0;
    while i < ArraySize(this.m_ocRows) {
      let on = s.weapon == i;
      let st = i < ArraySize(s.wStat) ? s.wStat[i] : "";
      this.m_ocRows[i].SetVisible(on);
      let dark = new HDRColor(0.01, 0.06, 0.03, 1.0);
      this.m_ocRowSta[i].SetTintColor(on ? dark : this.Lbl());
      this.m_ocRowNames[i].SetTintColor(on ? dark : this.Hi());
      this.m_ocRowSubs[i].SetTintColor(on ? dark : this.G());
      this.m_ocRowStats[i].SetText(st);
      this.m_ocRowStats[i].SetTintColor(on && !CMDroneHud.StatWarn(st) ? dark : CMDroneHud.StatColor(st));
      i += 1;
    }
    if ArraySize(this.m_ocRowSubs) >= 3 {
      this.m_ocRowSubs[0].SetText("X4   UNLTD");
      this.m_ocRowSubs[1].SetText("HEAT " + IntToString(RoundF(ClampF(s.secHeat, 0.0, 1.0) * 100.0)) + "%");
      this.m_ocRowSubs[2].SetText(IntToString(s.rkLeft) + " / " + IntToString(s.rkMax));
    }
    // the gunship banner
    this.m_holdBox.SetVisible(StrLen(s.holdText) > 0);
    this.m_holdT.SetText(s.holdText);
    this.m_windT.SetText(s.windText);
    // the airframe: the hull, the thrusters left, each part's colour
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.m_hullT.SetText("HULL " + IntToString(RoundF(hull * 100.0)) + "%");
    this.m_hullT.SetTintColor(CMDroneHud.Health(hull));
    if ArraySize(s.droneParts) >= 5 {
      let pods = 0;
      let k = 1;
      while k <= 4 {
        if s.droneParts[k] > 0.0 {
          pods += 1;
        }
        k += 1;
      }
      this.m_ocThr.SetText("THR " + IntToString(pods) + "/4");
      this.m_ocThr.SetTintColor(pods < 4 ? (pods < 3 ? CMPilotHud.Red() : CMPilotHud.Caution()) : this.Hi());
    }
    i = 0;
    while i < ArraySize(this.m_schemParts) {
      let hp = i < ArraySize(s.droneParts) ? s.droneParts[i] : 1.0;
      let img = this.m_schemParts[i];
      img.SetTintColor(hp <= 0.0 ? CMPilotHud.Grey() : CMDroneHud.Health(hp));
      img.SetOpacity(hp <= 0.0 ? 0.45 : 1.0);
      i += 1;
    }
    this.m_ocSensor = Equals(s.sensor, "DAY") ? "DAY-TV" : "IR // " + s.sensor;
    this.m_ocZoomed = s.zoomed;
    this.m_warnT.SetText(s.warning);
  }

  public static func StatWarn(st: String) -> Bool = Equals(st, "LOST") || Equals(st, "OVERHEAT") || StrBeginsWith(st, "RLD") || Equals(st, "OFF ARC") || Equals(st, "NO SOLN") || Equals(st, "HOT")

  // a station's status colour: ready green, waiting amber, lost red
  public static func StatColor(st: String) -> HDRColor {
    if Equals(st, "LOST") || Equals(st, "OVERHEAT") {
      return CMPilotHud.Red();
    }
    if StrBeginsWith(st, "RLD") || Equals(st, "OFF ARC") || Equals(st, "NO SOLN") || Equals(st, "HOT") {
      return CMPilotHud.Caution();
    }
    return CMPilotHud.Amber();
  }

  // ---- every frame from the drone: what its sensor sees (CMDroneSense) ----------------
  public func Track(t: ref<CMDroneTrack>) -> Void {
    if !IsDefined(this.m_droot) || !IsDefined(this.m_ocMap) {
      return;
    }
    let cx = this.m_W * 0.5;
    let cy = 1080.0;
    // the sensor block's laser and autotrack; the field of view
    this.m_ocLaser.SetText(t.aimOk ? "ARMED" : "SAFE");
    this.m_ocLaser.SetTintColor(t.aimOk ? CMPilotHud.Caution() : this.Lbl());
    let locked = IsDefined(t.lock);
    this.m_ocTrack.SetText(locked ? "ON" : "OFF");
    this.m_ocTrack.SetTintColor(locked ? CMPilotHud.Caution() : this.Lbl());
    this.m_ocLcue.SetVisible(t.aimOk);
    this.m_ocLasing.SetVisible(t.aimOk);
    // the target block
    if t.aimOk {
      let dx = t.aim.X - t.pos.X;
      let dy = t.aim.Y - t.pos.Y;
      let brg = Rad2Deg(AtanF(dx, dy));
      this.m_ocSlant.SetText(CMPilotHud.Pad4(RoundF(Vector4.Distance(t.pos, t.aim))) + " M");
      this.m_ocBrg.SetText(CMPilotHud.Pad3(CMInk.Hdg(brg)));
      let dh = RoundF(t.aim.Z - t.pos.Z);
      this.m_ocDh.SetText((dh >= 0 ? "+" : "") + IntToString(dh) + " M");
      let spd = locked ? Vector4.Length(t.lock.vel) * 3.6 : 0.0;
      this.m_ocSpd.SetText((spd < 10.0 ? "0" : "") + IntToString(RoundF(spd)) + " KM/H");
      this.m_ocTgtTag.SetText(spd > 3.0 ? "MOVING" : "STATIC");
    } else {
      this.m_ocSlant.SetText("---- M");
      this.m_ocBrg.SetText("---");
      this.m_ocDh.SetText("--- M");
      this.m_ocSpd.SetText("-- KM/H");
      this.m_ocTgtTag.SetText("NO LASE");
    }
    // the look-down angle
    let dep = ClampF(-t.camPitch, 0.0, 90.0);
    let ax = cx + 560.0;
    let ay = cy - 250.0;
    let a = Deg2Rad(270.0 - dep);
    let r = this.OC_DEP_R;
    CMInk.Seg(this.m_ocDepNeedle, ax + SinF(a) * (r - 34.0), ay - CosF(a) * (r - 34.0), ax + SinF(a) * (r + 10.0), ay - CosF(a) * (r + 10.0), 6.0);
    this.m_ocDepT.SetText("DEP " + IntToString(RoundF(dep)));
    // the mortar's spread on the ground: dashed, a leader up and right to its words
    let sp = t.ringOk && t.blastR > 0.0 && ArraySize(t.ring) == ArraySize(this.m_ocSplash);
    let topR = Vector2(0.0, 0.0);
    let best = -99999.0;
    let n = 0;
    while n < ArraySize(this.m_ocSplash) {
      let s = this.m_ocSplash[n];
      s.SetVisible(sp && n % 2 == 0);
      if sp {
        let p0 = t.ring[n];
        let p1 = t.ring[(n + 1) % ArraySize(t.ring)];
        CMInk.Seg(s, cx + p0.X, cy + p0.Y, cx + p1.X, cy + p1.Y, 3.0);
        let score = p0.X - p0.Y;
        if score > best {
          best = score;
          topR = Vector2(cx + p0.X, cy + p0.Y);
        }
      }
      n += 1;
    }
    this.m_ocLeader[0].SetVisible(sp);
    this.m_ocLeader[1].SetVisible(sp);
    this.m_ocSplashT.SetVisible(sp);
    this.m_ocSplashT2.SetVisible(sp);
    if sp {
      let kx = topR.X + 80.0;
      let ky = topR.Y - 80.0;
      CMInk.Seg(this.m_ocLeader[0], topR.X, topR.Y, kx, ky, 2.0);
      CMInk.Seg(this.m_ocLeader[1], kx, ky, kx + 260.0, ky, 2.0);
      this.m_ocSplashT.SetMargin(inkMargin(kx + 6.0, ky - 40.0, 0.0, 0.0));
      this.m_ocSplashT.SetText("MORTAR X4   SPREAD " + IntToString(RoundF(t.blastR)) + "M");
      this.m_ocSplashT2.SetMargin(inkMargin(kx + 6.0, ky + 8.0, 0.0, 0.0));
      this.m_ocSplashT2.SetText("TOF " + FloatToStringPrec(t.tof, 1) + " S");
    }
    // the situation map: north up round the drone, 100 m to its rim
    let c = this.OC_MAP_R;
    let k = this.OC_MPX;
    let lim = c - 8.0;
    this.m_ocSelf.SetRotation(-t.yaw);
    // the sensor's view on the ground as a wedge from the drone out to the far edge of its
    // footprint (the view's top corners: the mockup's cone)
    let fp: array<Vector2>;
    if t.footOk && ArraySize(t.foot) == 4 {
      ArrayPush(fp, Vector2(c, c));
      let f = 0;
      while f < 2 {
        let fx = (t.foot[f].X - t.pos.X) * k;
        let fy = -(t.foot[f].Y - t.pos.Y) * k;
        let len = SqrtF(fx * fx + fy * fy);
        if len > lim {
          fx *= lim / len;
          fy *= lim / len;
        }
        ArrayPush(fp, Vector2(c + fx, c + fy));
        f += 1;
      }
    }
    CMInk.FillPoly(this.m_ocFoot, fp);
    let ei = 0;
    while ei < ArraySize(this.m_ocFootEdge) {
      let eb = this.m_ocFootEdge[ei];
      eb.SetVisible(ArraySize(fp) == 3);
      if ArraySize(fp) == 3 {
        let p0 = fp[ei];
        let p1 = fp[(ei + 1) % 3];
        CMInk.Seg(eb, p0.X, p0.Y, p1.X, p1.Y, 3.0);
      }
      ei += 1;
    }
    // the sensor block's MTS line: its mode and field of view
    this.m_ocMts.SetText(this.m_ocSensor + "   " + (this.m_ocZoomed ? "NFOV " : "WFOV ") + FloatToStringPrec(t.fov, 1));
    // the target, and the orbit at the standoff round it
    let tx = 0.0;
    let ty = 0.0;
    let tOn = false;
    let standoff = 0.0;
    if t.aimOk {
      tx = (t.aim.X - t.pos.X) * k;
      ty = -(t.aim.Y - t.pos.Y) * k;
      standoff = SqrtF(tx * tx + ty * ty);
      tOn = standoff < lim;
    }
    this.m_ocTgtMark.SetVisible(tOn);
    this.m_ocTgtLbl.SetVisible(tOn);
    if tOn {
      this.m_ocTgtMark.SetMargin(inkMargin(c + tx - 12.0, c + ty - 12.0, 0.0, 0.0));
      this.m_ocTgtLbl.SetMargin(inkMargin(c + tx + 16.0, c + ty - 30.0, 0.0, 0.0));
    }
    let o = 0;
    while o < ArraySize(this.m_ocOrbit) {
      let s = this.m_ocOrbit[o];
      let show = tOn && t.hold && standoff > 6.0 && o % 2 == 0;
      s.SetVisible(show);
      if show {
        let a0 = Deg2Rad(Cast<Float>(o) * 11.25);
        let a1 = Deg2Rad(Cast<Float>(o + 1) * 11.25);
        CMInk.Seg(s, c + tx + SinF(a0) * standoff, c + ty - CosF(a0) * standoff, c + tx + SinF(a1) * standoff, c + ty - CosF(a1) * standoff, 3.0);
      }
      o += 1;
    }
    // the contacts; V as its blue dot
    this.m_ocV.SetVisible(false);
    this.m_ocVLbl.SetVisible(false);
    let i = 0;
    let nn = Min(ArraySize(t.contacts), ArraySize(this.m_ocDots));
    while i < nn {
      let ct = t.contacts[i];
      let dx = (ct.pos.X - t.pos.X) * k;
      let dy = -(ct.pos.Y - t.pos.Y) * k;
      let show = SqrtF(dx * dx + dy * dy) < lim;
      let d = this.m_ocDots[i];
      if ct.kind == 0 {
        d.SetVisible(false);
        this.m_ocV.SetVisible(show);
        this.m_ocVLbl.SetVisible(show);
        this.m_ocV.SetMargin(inkMargin(c + dx - 8.0, c + dy - 8.0, 0.0, 0.0));
        this.m_ocVLbl.SetMargin(inkMargin(c + dx + 12.0, c + dy - 14.0, 0.0, 0.0));
      } else {
        d.SetVisible(show);
        if show {
          d.SetMargin(inkMargin(c + dx - 7.0, c + dy - 7.0, 0.0, 0.0));
          d.SetTintColor(CMDroneHud.MapColor(ct.kind));
        }
      }
      i += 1;
    }
    while i < ArraySize(this.m_ocDots) {
      this.m_ocDots[i].SetVisible(false);
      i += 1;
    }
    // the BDA
    let acc = t.rounds > 0 ? RoundF(Cast<Float>(t.hits) * 100.0 / Cast<Float>(t.rounds)) : 0;
    this.m_ocBda.SetText("BDA   KIA " + IntToString(this.m_ocKills) + "   //   RDS " + IntToString(t.rounds) + "   HITS " + IntToString(t.hits) + "   ACC " + IntToString(acc) + "%   //   HOSTILES " + IntToString(t.hostiles));
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

  // every frame from the drone: the flight numbers
  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.m_droot) {
      return;
    }
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
      this.m_cross.SetTintColor(this.m_flashT > 0.0 ? CMPilotHud.Caution() : new HDRColor(1.0, 1.0, 1.0, 1.0));
    }
    if !IsDefined(this.m_droot) {
      return;
    }
    this.m_ocClock += dt;
    let ph = this.m_ocClock - Cast<Float>(FloorF(this.m_ocClock));
    this.m_ocRecDot.SetOpacity(ph < 0.5 ? 1.0 : 0.15);
    // a threat's bearing: on the tape while it is in view, 3 s
    if this.m_ocThreatT > 0.0 {
      this.m_ocThreatT -= dt;
      let rel = this.m_ocThreatB - this.m_ocHeading;
      while rel > 180.0 { rel -= 360.0; }
      while rel < -180.0 { rel += 360.0; }
      let x = this.m_W * 0.5 + rel * this.HDG_PX;
      this.m_ocThreatTick.SetVisible(this.m_ocThreatT > 0.0 && AbsF(rel * this.HDG_PX) <= 600.0);
      this.m_ocThreatTick.SetMargin(inkMargin(x - 4.0, 136.0, 0.0, 0.0));
      this.m_ocThreat.SetText(this.m_ocThreatT > 0.0 ? "THREAT  " + CMPilotHud.Pad3(CMInk.Hdg(this.m_ocThreatB)) : "");
      let tp = this.m_ocThreatT * 2.0;
      this.m_ocThreat.SetOpacity(tp - Cast<Float>(FloorF(tp)) < 0.6 ? 1.0 : 0.4);
    } else {
      this.m_ocThreatTick.SetVisible(false);
      this.m_ocThreat.SetText("");
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
