// =============================================================================
// MECHS OF NIGHT CITY - THE BOMBUS'S DISPLAY: A CHEAP FPV OSD (0.7.1)
//
// Each drone's display befits its role (Omar). The Bombus is a kamikaze FPV: its display is
// a real FPV drone's on-screen display gone street-grade cyberpunk, laid out as goggles see
// it: a 16:9 feed in the middle of the screen, whatever the screen's shape, scanlined, its
// edges darkened, a band of interference rolling down it. White outlined text, one cyan
// accent (affiliation colours come later, with hijacking: Omar).
//   top left      the airframe's name; the 4S pack as four cells and its voltage; signal
//                 bars, RSSI and LQ
//   top centre    a compass strip: the heading and the points either side
//   top right     the flight timer, the flight mode (ANGLE / HORIZON / ACRO), REC, the
//                 video channel
//   centre        a small -+- crosshair and the home arrow under it (where V is) with the
//                 distance; no horizon line (Omar)
//   left / right  speed, and height with the vertical speed, each in a bracket
//   bottom left   the attitude in a small boxed horizon, the throttle as a gauge beside it
//   bottom centre the payload, ARMED / RELEASED, the key; warnings above the crosshair
//   bottom right  the airframe: the Bombus scanned from its own meshes, tinted by the hull
// It takes the same calls as CMDroneHud (which it extends) and draws none of that
// display; no field shares a name with CMDroneHud's or CMPilotHud's (a49).
// =============================================================================
module ControllableMechs

import Codeware.UI.ScreenHelper

public class CMBombusHud extends CMDroneHud {
  private let m_fRoot: ref<inkCanvas>;
  private let m_fParent: wref<inkCompoundWidget>;
  private let m_fHidden: array<wref<inkWidget>>;
  private let m_fHiddenOp: array<Float>;
  private let m_fW: Float;
  private let m_fX0: Float;             // the feed's left edge (16:9 in the middle)
  private let m_fTexts: array<ref<inkText>>;     // each OSD line, and its shadow
  private let m_fShadows: array<ref<inkText>>;
  private let m_fAhi: ref<inkCanvas>;   // the boxed horizon's bar
  private let m_fHome: ref<inkCanvas>;  // the home arrow
  private let m_fSprite: array<ref<inkImage>>;
  private let m_fRec: ref<inkImage>;
  private let m_fCells: array<ref<inkImage>>;
  private let m_fBars: array<ref<inkImage>>;
  private let m_fThrS: ref<CMSlider>;
  private let m_fBand: ref<inkRectangle>;
  private let m_fClock: Float;          // s flown (the OSD timer, the battery's sag)
  private let m_fBlink: Float;
  private let m_fHitT: Float;
  private let m_fBoot: Float;
  // the strike pieces (round 2): the target's brackets and range, the blast ring, the arming
  // strip and the impact countdown, the motor bars
  private let m_fTgtBars: array<ref<inkRectangle>>;
  private let m_fTgtT: ref<inkText>;
  private let m_fTgtD: ref<inkText>;
  private let m_fRingSegs: array<ref<inkImage>>;
  private let m_fRingT: ref<inkText>;
  private let m_fRingFill: array<ref<inkRectangle>>;   // the blast zone, filled (a50)
  private let m_fArmS: ref<CMSlider>;
  private let m_fTti: ref<inkText>;
  private let m_fMotS: array<ref<CMSlider>>;

  // the OSD lines (m_fTexts indices)
  private let T_NAME: Int32 = 0;
  private let T_BAT: Int32 = 1;
  private let T_LINK: Int32 = 2;
  private let T_TIME: Int32 = 3;
  private let T_MODE: Int32 = 4;
  private let T_SPD: Int32 = 5;
  private let T_ALT: Int32 = 6;
  private let T_THR: Int32 = 7;
  private let T_PAY: Int32 = 8;
  private let T_ARM: Int32 = 9;
  private let T_WARN: Int32 = 10;
  private let T_HINT: Int32 = 11;
  private let T_REC: Int32 = 12;
  private let T_VS: Int32 = 13;
  private let T_HDG: Int32 = 14;
  private let T_CMPL: Int32 = 15;
  private let T_CMPR: Int32 = 16;
  private let T_HOME: Int32 = 17;
  private let T_VTX: Int32 = 18;
  private let T_HULL: Int32 = 19;
  private let T_PIT: Int32 = 20;

  protected func Ink() -> HDRColor = new HDRColor(1.0, 1.0, 1.0, 1.0)
  protected func Acc() -> HDRColor = new HDRColor(0.30, 1.00, 1.10, 1.0)
  protected func Blk() -> HDRColor = new HDRColor(0.0, 0.0, 0.0, 1.0)

  // for the other drones' displays built on this one (CMGriffinHud, CMWyvernHud): the
  // design width, and the 16:9 area's left edge
  protected func FW() -> Float = this.m_fW
  protected func FX0() -> Float = this.m_fX0
  protected func FRoot() -> ref<inkCanvas> = this.m_fRoot

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
    this.m_fParent = window;
    ArrayClear(this.m_fHidden);
    ArrayClear(this.m_fHiddenOp);
    let i = 0;
    while i < window.GetNumChildren() {
      let child = window.GetWidgetByIndex(i);
      if IsDefined(child) && NotEquals(child.GetName(), n"cm_bombus_hud") {
        ArrayPush(this.m_fHidden, child);
        ArrayPush(this.m_fHiddenOp, child.GetOpacity());
        child.SetOpacity(0.0);
      }
      i += 1;
    }
    let root = new inkCanvas();
    root.SetName(n"cm_bombus_hud");
    root.SetInteractive(false);
    let screen = ScreenHelper.GetScreenSize(GetGameInstance());
    this.m_fW = 3840.0;
    if screen.Y > 100.0 {
      let k = screen.Y / 2160.0;
      this.m_fW = screen.X / k;
      root.SetAnchor(inkEAnchor.TopLeft);
      root.SetSize(Vector2(this.m_fW, 2160.0));
      root.SetRenderTransformPivot(Vector2(0.0, 0.0));
      root.SetScale(Vector2(k, k));
    } else {
      root.SetAnchor(inkEAnchor.Fill);
    }
    root.Reparent(window);
    this.m_fRoot = root;
    // the feed: 16:9 in the middle, as goggles show it (on a 32:9 screen the OSD sat in
    // the far corners)
    this.m_fX0 = MaxF(0.0, this.m_fW * 0.5 - 1920.0);
    this.BuildFeed(root);
    this.BuildOsd(root);
    this.BuildSprite(root);
    return true;
  }

  public func Remove() -> Void {
    if IsDefined(this.m_fRoot) && IsDefined(this.m_fParent) {
      this.m_fRoot.StopAllAnimations();
      this.m_fParent.RemoveChild(this.m_fRoot);
    }
    this.m_fRoot = null;
    let i = 0;
    while i < ArraySize(this.m_fHidden) {
      let w = this.m_fHidden[i];
      if IsDefined(w) {
        w.SetOpacity(this.m_fHiddenOp[i]);
      }
      i += 1;
    }
    ArrayClear(this.m_fHidden);
    ArrayClear(this.m_fHiddenOp);
    ArrayClear(this.m_fTexts);
    ArrayClear(this.m_fShadows);
    ArrayClear(this.m_fSprite);
    ArrayClear(this.m_fCells);
    ArrayClear(this.m_fBars);
    ArrayClear(this.m_fTgtBars);
    ArrayClear(this.m_fRingSegs);
    ArrayClear(this.m_fMotS);
  }

  // the cheap analog feed: scanlines over everything, the edges darkened, a band of
  // interference rolling down
  protected func BuildFeed(root: ref<inkCanvas>) -> Void {
    let y = 0.0;
    while y < 2160.0 {
      CMPilotHud.Bar(root, 0.0, y, this.m_fW, 2.0, this.Blk(), 0.10);
      y += 7.0;
    }
    let e = 0;
    while e < 4 {
      let d = Cast<Float>(e) * 40.0;
      CMPilotHud.Bar(root, 0.0, d, this.m_fW, 40.0, this.Blk(), 0.10);
      CMPilotHud.Bar(root, 0.0, 2120.0 - d, this.m_fW, 40.0, this.Blk(), 0.10);
      CMPilotHud.Bar(root, d, 0.0, 40.0, 2160.0, this.Blk(), 0.10);
      CMPilotHud.Bar(root, this.m_fW - 40.0 - d, 0.0, 40.0, 2160.0, this.Blk(), 0.10);
      e += 1;
    }
    this.m_fBand = CMPilotHud.Bar(root, 0.0, 0.0, this.m_fW, 26.0, this.Ink(), 0.05);
  }

  // a line of OSD text with its black shadow (align 0 left, 1 centred, 2 right)
  protected func Osd(root: ref<inkCanvas>, x: Float, y: Float, size: Int32, align: Int32) -> Void {
    let sh = CMPilotHud.Label(root, inkEAnchor.TopLeft, x + 3.0, y + 3.0, "", size, n"Semi-Bold", this.Blk());
    let t = CMPilotHud.Label(root, inkEAnchor.TopLeft, x, y, "", size, n"Semi-Bold", this.Ink());
    sh.SetOpacity(0.85);
    if align != 0 {
      let a = align == 1 ? 0.5 : 1.0;
      sh.SetAnchorPoint(Vector2(a, 0.0));
      t.SetAnchorPoint(Vector2(a, 0.0));
    }
    ArrayPush(this.m_fTexts, t);
    ArrayPush(this.m_fShadows, sh);
  }

  protected func SetT(i: Int32, text: String) -> Void {
    if i < ArraySize(this.m_fTexts) {
      this.m_fTexts[i].SetText(text);
      this.m_fShadows[i].SetText(text);
    }
  }

  protected func Tint(i: Int32, c: HDRColor) -> Void {
    if i < ArraySize(this.m_fTexts) {
      this.m_fTexts[i].SetTintColor(c);
    }
  }

  // a thin bracket frame: the four corners of a box
  protected func Brackets(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float) -> Void {
    let L = 26.0;
    let c = this.Acc();
    CMPilotHud.Bar(root, x, y, L, 3.0, c, 0.8);
    CMPilotHud.Bar(root, x, y, 3.0, L, c, 0.8);
    CMPilotHud.Bar(root, x + w - L, y, L, 3.0, c, 0.8);
    CMPilotHud.Bar(root, x + w - 3.0, y, 3.0, L, c, 0.8);
    CMPilotHud.Bar(root, x, y + h - 3.0, L, 3.0, c, 0.8);
    CMPilotHud.Bar(root, x, y + h - L, 3.0, L, c, 0.8);
    CMPilotHud.Bar(root, x + w - L, y + h - 3.0, L, 3.0, c, 0.8);
    CMPilotHud.Bar(root, x + w - 3.0, y + h - L, 3.0, L, c, 0.8);
  }

  protected func BuildOsd(root: ref<inkCanvas>) -> Void {
    let x0 = this.m_fX0;
    let x1 = x0 + MinF(3840.0, this.m_fW);
    let cx = this.m_fW * 0.5;
    let cy = 1080.0;
    // in m_fTexts' order (T_*)
    this.Osd(root, x0 + 200.0, 150.0, 36, 0);          // name
    this.Osd(root, x0 + 380.0, 200.0, 50, 0);          // battery
    this.Osd(root, x0 + 380.0, 274.0, 32, 0);          // link
    this.Osd(root, x1 - 200.0, 150.0, 54, 2);          // timer
    this.Osd(root, x1 - 200.0, 218.0, 34, 2);          // mode
    this.Osd(root, cx - 820.0, 1040.0, 52, 2);         // speed
    this.Osd(root, cx + 820.0, 1040.0, 52, 0);         // height
    this.Osd(root, x0 + 560.0, 1990.0, 30, 1);         // throttle
    this.Osd(root, cx, 1810.0, 44, 1);                 // payload
    this.Osd(root, cx, 1870.0, 60, 1);                 // ARMED
    this.Osd(root, cx, 820.0, 54, 1);                  // warnings
    this.Osd(root, cx, 1946.0, 30, 1);                 // the key
    this.Osd(root, x1 - 248.0, 266.0, 32, 2);          // REC
    this.Osd(root, cx + 820.0, 1104.0, 32, 0);         // vertical speed
    this.Osd(root, cx, 150.0, 48, 1);                  // heading
    this.Osd(root, cx - 330.0, 158.0, 34, 1);          // compass, the point left
    this.Osd(root, cx + 330.0, 158.0, 34, 1);          // compass, the point right
    this.Osd(root, cx, 1210.0, 32, 1);                 // home distance
    this.Osd(root, x1 - 200.0, 314.0, 28, 2);          // video channel
    this.Osd(root, x1 - 355.0, 1990.0, 30, 1);         // hull
    this.Osd(root, x0 + 345.0, 1990.0, 30, 1);         // pitch / roll
    // the pack: four cells, the signal: five bars
    let c = 0;
    while c < 4 {
      let bx = x0 + 200.0 + Cast<Float>(c) * 42.0;
      CMKit.Fill(root, bx, 206.0, 36.0, 58.0, CMInk.Glass(), CMInk.GlassOp());
      ArrayPush(this.m_fCells, CMKit.Fill(root, bx + 4.0, 210.0, 28.0, 50.0, this.Acc(), 1.0));
      c += 1;
    }
    CMKit.Fill(root, x0 + 368.0, 222.0, 10.0, 26.0, this.Ink(), 0.9);   // the pack's terminal
    let b = 0;
    while b < 5 {
      let h = 10.0 + Cast<Float>(b) * 8.0;
      ArrayPush(this.m_fBars, CMKit.VPill(root, x0 + 200.0 + Cast<Float>(b) * 30.0, 312.0 - h, 18.0, h, this.Ink(), 1.0));
      b += 1;
    }
    this.Brackets(root, x0 + 180.0, 136.0, 620.0, 196.0);
    this.Brackets(root, x1 - 560.0, 136.0, 380.0, 220.0);
    // the compass strip's ticks and its centre caret
    let k = -6;
    while k <= 6 {
      let tall = k % 3 == 0;
      CMPilotHud.Bar(root, cx + Cast<Float>(k) * 55.0 - 2.0, 214.0, 4.0, tall ? 26.0 : 14.0, this.Ink(), 0.8);
      k += 1;
    }
    CMPilotHud.Bar(root, cx - 2.0, 244.0, 4.0, 22.0, this.Acc(), 1.0);
    // speed and height in brackets either side of the crosshair
    this.Brackets(root, cx - 1060.0, 1020.0, 260.0, 120.0);
    this.Brackets(root, cx + 800.0, 1020.0, 260.0, 120.0);
    // the crosshair: a small -+-
    CMPilotHud.Bar(root, cx - 70.0, cy - 2.0, 44.0, 4.0, this.Ink(), 0.95);
    CMPilotHud.Bar(root, cx + 26.0, cy - 2.0, 44.0, 4.0, this.Ink(), 0.95);
    CMPilotHud.Bar(root, cx - 2.0, cy - 14.0, 4.0, 28.0, this.Ink(), 0.95);
    // the home arrow under it: a chevron turned toward V
    let home = new inkCanvas();
    home.SetMargin(inkMargin(cx - 40.0, 1130.0, 0.0, 0.0));
    home.SetSize(Vector2(80.0, 80.0));
    home.SetRenderTransformPivot(Vector2(0.5, 0.5));
    home.Reparent(root);
    let l = CMPilotHud.Bar(home, 18.0, 30.0, 34.0, 6.0, this.Acc(), 1.0);
    l.SetRotation(-45.0);
    let r = CMPilotHud.Bar(home, 30.0, 30.0, 34.0, 6.0, this.Acc(), 1.0);
    r.SetRotation(45.0);
    CMPilotHud.Bar(home, 37.0, 30.0, 6.0, 34.0, this.Acc(), 1.0);
    this.m_fHome = home;
    // the attitude: a small boxed horizon, bottom left (Omar: no line across the middle)
    let ax = x0 + 220.0;
    let ay = 1740.0;
    let box = new inkCanvas();
    box.SetMargin(inkMargin(ax, ay, 0.0, 0.0));
    box.SetSize(Vector2(250.0, 220.0));
    box.Reparent(root);
    CMKit.Box(box, 0.0, 0.0, 250.0, 220.0, this.Acc(), 0.0);
    this.Brackets(root, ax, ay, 250.0, 220.0);
    let bar = new inkCanvas();
    bar.SetMargin(inkMargin(25.0, 108.0, 0.0, 0.0));
    bar.SetSize(Vector2(200.0, 4.0));
    bar.SetRenderTransformPivot(Vector2(0.5, 0.5));
    bar.Reparent(box);
    CMKit.Pill(bar, 0.0, -1.0, 200.0, 6.0, this.Acc(), 1.0);
    CMPilotHud.Bar(bar, 96.0, 4.0, 8.0, 14.0, this.Acc(), 0.7);     // the ground side
    this.m_fAhi = bar;
    // the aircraft symbol fixed in the middle of the box
    CMPilotHud.Bar(box, 70.0, 108.0, 40.0, 4.0, this.Ink(), 1.0);
    CMPilotHud.Bar(box, 140.0, 108.0, 40.0, 4.0, this.Ink(), 1.0);
    CMPilotHud.Bar(box, 122.0, 104.0, 6.0, 12.0, this.Ink(), 1.0);
    // the throttle gauge beside it
    let tx = ax + 290.0;
    CMKit.Fill(root, tx, ay, 40.0, 220.0, CMInk.Glass(), CMInk.GlassOp());
    this.Brackets(root, tx - 6.0, ay - 6.0, 52.0, 232.0);
    this.m_fThrS = CMSlider.Make(root, tx + 8.0, ay + 8.0, 24.0, 204.0, true, this.Acc());
    this.m_fRec = CMKit.Disc(root, x1 - 224.0, 286.0, 12.0, CMPilotHud.Red(), 1.0);
    this.SetT(this.T_HINT, "[LMB] DETONATE");
    this.SetT(this.T_REC, "REC");
    this.SetT(this.T_VTX, "CH R7  5917  600MW");
    this.Tint(this.T_ARM, this.Acc());
    this.Tint(this.T_WARN, CMPilotHud.Red());
    this.BuildStrike(root, ax, ay, tx);
  }

  // the strike pieces: the target's brackets and range, the blast ring, the arming strip and
  // the impact countdown, the motor bars beside the throttle
  private func BuildStrike(root: ref<inkCanvas>, ax: Float, ay: Float, tx: Float) -> Void {
    let cx = this.m_fW * 0.5;
    let n = 0;
    while n < 8 {
      ArrayPush(this.m_fTgtBars, CMPilotHud.Bar(root, 0.0, 0.0, 4.0, 4.0, this.Ink(), 1.0));
      n += 1;
    }
    this.m_fTgtT = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 30, n"Semi-Bold", this.Ink());
    this.m_fTgtT.SetAnchorPoint(Vector2(0.5, 1.0));
    this.m_fTgtD = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 30, n"Semi-Bold", this.Ink());
    this.m_fTgtD.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_fRingFill = CMInk.FillBars(root, 64, CMPilotHud.Caution(), 0.2);
    n = 0;
    while n < 32 {
      ArrayPush(this.m_fRingSegs, CMKit.Stroke(root, CMPilotHud.Caution(), 0.9));
      n += 1;
    }
    this.m_fRingT = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 28, n"Semi-Bold", CMPilotHud.Caution());
    this.m_fRingT.SetAnchorPoint(Vector2(0.5, 1.0));
    // the arming strip: one smooth bar across the bottom (a52), the countdown over it
    this.m_fArmS = CMSlider.Make(root, cx - 350.0, 1772.0, 700.0, 20.0, false, CMPilotHud.Caution());
    this.Brackets(root, cx - 366.0, 1760.0, 728.0, 44.0);
    this.m_fTti = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx, 1706.0, "", 40, n"Semi-Bold", this.Ink());
    this.m_fTti.SetAnchorPoint(Vector2(0.5, 0.0));
    // the motor bars, right of the throttle
    let m = 0;
    while m < 4 {
      let mx = tx + 80.0 + Cast<Float>(m) * 44.0;
      CMKit.Fill(root, mx, ay, 30.0, 220.0, CMInk.Glass(), CMInk.GlassOp());
      ArrayPush(this.m_fMotS, CMSlider.Make(root, mx + 6.0, ay + 8.0, 18.0, 204.0, true, this.Acc()));
      let l = CMPilotHud.Label(root, inkEAnchor.TopLeft, mx + 15.0, ay - 36.0, "M" + IntToString(m + 1), 22, n"Semi-Bold", this.Ink());
      l.SetAnchorPoint(Vector2(0.5, 0.0));
      m += 1;
    }
    this.Brackets(root, tx + 70.0, ay - 44.0, 186.0, 270.0);
    this.FTgtShow(false);
  }

  private func FTgtShow(on: Bool) -> Void {
    for b in this.m_fTgtBars {
      b.SetVisible(on);
    }
    this.m_fTgtT.SetVisible(on);
    this.m_fTgtD.SetVisible(on);
  }

  // every frame: what the reticle is on, the blast ring, the strip, the motors
  public func Track(t: ref<CMDroneTrack>) -> Void {
    if !IsDefined(this.m_fRoot) || ArraySize(this.m_fTgtBars) < 8 {
      return;
    }
    let cx = this.m_fW * 0.5;
    let cy = 1080.0;
    // the target: brackets round it, its kind over them, its range under
    let c = t.lock;
    if IsDefined(c) && c.OnScreen() {
      this.FTgtShow(true);
      let col = c.kind == 2 ? CMPilotHud.Red() : CMInk.KindColor(c.kind, this.Acc());
      let scale = 1080.0 / TanF(Deg2Rad(MaxF(1.0, t.fov) * 0.5));
      let hh = ClampF(1.9 / MaxF(1.0, c.dist) * scale, 70.0, 600.0);
      let hw = MaxF(60.0, hh * 0.55);
      let x = cx + c.scr.X - hw * 0.5;
      let y = cy + c.scr.Y - hh * 0.5;
      let L = MinF(40.0, hw * 0.4);
      this.FBar(0, x, y, L, 5.0, col);
      this.FBar(1, x, y, 5.0, L, col);
      this.FBar(2, x + hw - L, y, L, 5.0, col);
      this.FBar(3, x + hw - 5.0, y, 5.0, L, col);
      this.FBar(4, x, y + hh - 5.0, L, 5.0, col);
      this.FBar(5, x, y + hh - L, 5.0, L, col);
      this.FBar(6, x + hw - L, y + hh - 5.0, L, 5.0, col);
      this.FBar(7, x + hw - 5.0, y + hh - L, 5.0, L, col);
      this.m_fTgtT.SetMargin(inkMargin(x + hw * 0.5, y - 8.0, 0.0, 0.0));
      this.m_fTgtT.SetText("TGT // " + c.Label());
      this.m_fTgtT.SetTintColor(col);
      this.m_fTgtD.SetMargin(inkMargin(x + hw * 0.5, y + hh + 8.0, 0.0, 0.0));
      this.m_fTgtD.SetText(IntToString(RoundF(c.dist)) + " M");
      this.m_fTgtD.SetTintColor(col);
    } else {
      this.FTgtShow(false);
    }
    // the blast ring on the ground round the reticle's point; red with V inside it
    let ring = t.armed && t.ringOk && ArraySize(t.ring) == ArraySize(this.m_fRingSegs);
    let vIn = false;
    if ArraySize(t.contacts) > 0 && t.contacts[0].kind == 0 && t.aimOk {
      vIn = Vector4.Distance(t.contacts[0].pos, t.aim) <= t.blastR + 1.0;
    }
    let rc = vIn ? CMPilotHud.Red() : CMPilotHud.Caution();
    let top = 99999.0;
    let topX = cx;
    let i = 0;
    while i < ArraySize(this.m_fRingSegs) {
      let b = this.m_fRingSegs[i];
      b.SetVisible(ring);
      if ring {
        let p = t.ring[i];
        let q = t.ring[(i + 1) % ArraySize(t.ring)];
        CMInk.Seg(b, cx + p.X, cy + p.Y, cx + q.X, cy + q.Y, 4.0);
        b.SetTintColor(rc);
        if p.Y < top {
          top = p.Y;
          topX = p.X;
        }
      }
      i += 1;
    }
    let fill: array<Vector2>;
    if ring {
      for o in t.ring {
        ArrayPush(fill, Vector2(cx + o.X, cy + o.Y));
      }
    }
    CMInk.FillPoly(this.m_fRingFill, fill);
    for fb in this.m_fRingFill {
      fb.SetTintColor(rc);
    }
    this.m_fRingT.SetVisible(ring);
    if ring {
      this.m_fRingT.SetMargin(inkMargin(cx + topX, cy + top - 8.0, 0.0, 0.0));
      this.m_fRingT.SetText(vIn ? "DANGER CLOSE // V IN BLAST" : "BLAST " + IntToString(RoundF(t.blastR)) + " M");
      this.m_fRingT.SetTintColor(rc);
    }
    // the arming strip and the countdown: dim while safe, lit while armed, flashing red in
    // the last 2 s before impact
    let ph = t.now * 4.0 - Cast<Float>(FloorF(t.now * 4.0));
    let close = t.armed && t.tti >= 0.0 && t.tti < 2.0;
    this.m_fArmS.Set(t.armed ? 1.0 : 0.0, close || vIn ? CMPilotHud.Red() : CMPilotHud.Caution());
    this.m_fArmS.fill.SetOpacity(close && ph > 0.5 ? 0.3 : 1.0);
    if !t.armed {
      this.m_fTti.SetText(t.blastR > 0.0 ? "" : "NO PAYLOAD");
    } else {
      this.m_fTti.SetText(t.tti >= 0.0 ? "IMPACT T-" + FloatToStringPrec(t.tti, 1) + " S" : "IMPACT --.- S");
    }
    this.m_fTti.SetTintColor(close ? CMPilotHud.Red() : this.Ink());
    // the motors
    let m = 0;
    while m < ArraySize(this.m_fMotS) {
      let v = m < ArraySize(t.motors) ? ClampF(t.motors[m], 0.0, 1.0) : 0.0;
      this.m_fMotS[m].Set(v, v > 0.95 ? CMPilotHud.Red() : this.Acc());
      m += 1;
    }
  }

  private func FBar(i: Int32, x: Float, y: Float, w: Float, h: Float, c: HDRColor) -> Void {
    let b = this.m_fTgtBars[i];
    b.SetMargin(inkMargin(x, y, 0.0, 0.0));
    b.SetSize(Vector2(w, h));
    b.SetTintColor(c);
  }

  // the airframe, scanned from the Bombus's own meshes, bottom right
  protected func BuildSprite(root: ref<inkCanvas>) -> Void {
    // (a49, Omar: three-quarter, as the Wyvern's: rounder, less blocky than top-down)
    let x1 = this.m_fX0 + MinF(3840.0, this.m_fW);
    let k = 260.0 / 360.0;
    let bx = x1 - 200.0 - 408.0 * k;
    let by = 1700.0;
    this.Brackets(root, bx - 20.0, by - 20.0, 408.0 * k + 40.0, 300.0);
    let box = new inkCanvas();
    box.SetMargin(inkMargin(bx, by, 0.0, 0.0));
    box.SetSize(Vector2(408.0 * k, 260.0));
    box.Reparent(root);
    this.Layer(box, k, n"bombus_arm_back", 81.0, 5.0, 137.0, 99.0);
    this.Layer(box, k, n"bombus_arm_l", 297.0, 69.0, 107.0, 119.0);
    this.Layer(box, k, n"bombus_arm_r", 5.0, 156.0, 139.0, 112.0);
    this.Layer(box, k, n"bombus_body", 82.0, 40.0, 253.0, 253.0);
    this.Layer(box, k, n"bombus_payload", 191.0, 205.0, 130.0, 150.0);
  }

  protected func Layer(box: ref<inkCanvas>, k: Float, name: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
    let img = new inkImage();
    img.SetAtlasResource(CMDroneHud.Atlas());
    img.SetTexturePart(name);
    img.SetMargin(inkMargin(x * k, y * k, 0.0, 0.0));
    img.SetSize(Vector2(w * k, h * k));
    img.SetTintColor(this.Acc());
    img.SetInteractive(false);
    img.Reparent(box);
    ArrayPush(this.m_fSprite, img);
  }

  // the compass point nearest a heading (0 north, clockwise)
  private static func Point(h: Int32) -> String {
    let p = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    let i = ((h + 22) / 45) % 8;
    return p[i];
  }

  // ---- each frame / tick -----------------------------------------------------------
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.m_fRoot) {
      return;
    }
    this.SetT(this.T_NAME, s.title);
    let sig = ClampF(s.signal, 0.0, 1.0);
    this.SetT(this.T_LINK, "RSSI " + IntToString(RoundF(sig * 99.0)) + "  LQ " + IntToString(Clamp(RoundF(sig * 100.0) + 1, 0, 100)));
    let n = 0;
    while n < ArraySize(this.m_fBars) {
      this.m_fBars[n].SetOpacity(sig * 5.0 > Cast<Float>(n) + 0.5 ? 1.0 : 0.2);
      n += 1;
    }
    this.SetT(this.T_PAY, s.priText);
    this.SetT(this.T_ARM, s.secText);
    this.SetT(this.T_MODE, s.terText);
    // the compass strip: the heading, and the points 90 degrees either side
    let h = (s.heading % 360 + 360) % 360;
    this.SetT(this.T_HDG, (h < 100 ? (h < 10 ? "00" : "0") : "") + IntToString(h) + " " + CMBombusHud.Point(h));
    this.SetT(this.T_CMPL, CMBombusHud.Point((h + 270) % 360));
    this.SetT(this.T_CMPR, CMBombusHud.Point((h + 90) % 360));
    // home: the arrow toward V, and how far
    if s.home < 900.0 {
      this.m_fHome.SetVisible(true);
      this.m_fHome.SetRotation(s.home + 180.0);
      this.SetT(this.T_HOME, "HOME " + IntToString(RoundF(s.distance)) + "M");
    } else {
      this.m_fHome.SetVisible(false);
      this.SetT(this.T_HOME, "");
    }
    // the warnings: the link first, then the hull, then anything the drone says
    let warn = s.warning;
    if sig < 0.35 {
      warn = "LINK WEAK";
    } else {
      if s.integrity < 0.3 {
        warn = "HULL CRITICAL";
      }
    }
    this.SetT(this.T_WARN, warn);
    // the airframe tinted by the hull
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.SetT(this.T_HULL, "AIRFRAME " + IntToString(RoundF(hull * 100.0)) + "%");
    let c = hull < 0.3 ? CMPilotHud.Red() : (hull < 0.6 ? CMPilotHud.Caution() : this.Acc());
    for img in this.m_fSprite {
      img.SetTintColor(c);
    }
    // the throttle gauge
    let thr = ClampF(s.spool, 0.0, 1.0);
    this.m_fThrS.Set(thr, this.Acc());
    this.SetT(this.T_THR, "THR " + IntToString(RoundF(thr * 100.0)) + "%");
  }

  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.m_fRoot) {
      return;
    }
    // the boxed horizon: rolls with the drone and rides up and down with its pitch
    this.m_fAhi.SetRotation(-roll);
    this.m_fAhi.SetMargin(inkMargin(25.0, 108.0 + ClampF(pitch, -45.0, 45.0) * 2.0, 0.0, 0.0));
    this.SetT(this.T_PIT, "P " + IntToString(RoundF(pitch)) + "  R " + IntToString(RoundF(roll)));
    this.SetT(this.T_SPD, IntToString(RoundF(speed * 3.6)) + " KMH");
    this.SetT(this.T_ALT, alt >= 0.0 ? FloatToStringPrec(alt, 1) + " M" : "--- M");
    this.SetT(this.T_VS, (vs >= 0.0 ? "+" : "") + FloatToStringPrec(vs, 1) + " M/S");
  }

  public func SetAttitude(heading: Float, pitch: Float) -> Void {}
  public func SetImpact(on: Bool, x: Float, y: Float, tof: Float) -> Void {}

  public func StartBoot() -> Void {
    this.m_fBoot = 1.2;
    this.m_fClock = 0.0;
    if IsDefined(this.m_fRoot) {
      this.m_fRoot.SetOpacity(0.0);
    }
  }

  // every frame: the timer, the 4S pack sagging as it flies, the REC dot, the rolling
  // interference band, the boot fade-in
  public func Boot(dt: Float) -> Void {
    if !IsDefined(this.m_fRoot) {
      return;
    }
    this.m_fClock += dt;
    this.m_fBlink += dt;
    if this.m_fBoot > 0.0 {
      this.m_fBoot = MaxF(0.0, this.m_fBoot - dt);
      this.m_fRoot.SetOpacity(1.0 - this.m_fBoot / 1.2);
    }
    let secs = FloorF(this.m_fClock);
    let mm = secs / 60;
    let ss = secs % 60;
    this.SetT(this.T_TIME, (mm < 10 ? "0" : "") + IntToString(mm) + ":" + (ss < 10 ? "0" : "") + IntToString(ss));
    let cell = MaxF(3.3, 4.2 - this.m_fClock / 240.0 * 0.8);
    this.SetT(this.T_BAT, FloatToStringPrec(cell * 4.0, 1) + "V");
    let frac = ClampF((cell - 3.3) / 0.9, 0.0, 1.0);
    let i = 0;
    while i < ArraySize(this.m_fCells) {
      // the cells empty from the right
      let on = frac * 4.0 > Cast<Float>(i) + 0.15;
      this.m_fCells[i].SetOpacity(on ? 1.0 : 0.12);
      this.m_fCells[i].SetTintColor(frac < 0.25 ? CMPilotHud.Red() : this.Acc());
      i += 1;
    }
    let ph = this.m_fBlink - Cast<Float>(FloorF(this.m_fBlink));
    this.m_fRec.SetOpacity(ph < 0.5 ? 1.0 : 0.15);
    // the interference band rolls down the feed every 3.5 s
    let roll = this.m_fBlink / 3.5;
    this.m_fBand.SetMargin(inkMargin(0.0, (roll - Cast<Float>(FloorF(roll))) * 2160.0, 0.0, 0.0));
    if this.m_fHitT > 0.0 {
      this.m_fHitT = MaxF(0.0, this.m_fHitT - dt);
      this.m_fBand.SetOpacity(this.m_fHitT > 0.0 ? 0.25 : 0.05);
    }
  }

  // a round of ours connected: the feed flares, as a cheap camera's does
  public func Hit(kill: Bool) -> Void {
    this.m_fHitT = kill ? 0.25 : 0.1;
  }
}
