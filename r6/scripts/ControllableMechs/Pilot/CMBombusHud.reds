// =============================================================================
// MECHS OF NIGHT CITY - THE BOMBUS'S DISPLAY: A CHEAP FPV OSD (0.7.1)
//
// Each drone's display befits its role (Omar). The Bombus is a kamikaze FPV: its display is
// a real FPV drone's on-screen display gone street-grade cyberpunk: white outlined text on
// a noisy analog feed, the drone's own name and battery top left, the flight timer and a
// recording dot top right, a small crosshair and a dashed horizon that tilts with the
// drone, speed and height either side, the payload and its arming at the bottom, and the
// Bombus itself bottom right (the scan of its own meshes: body, three rotor arms, the
// payload unit) tinted by the hull. One accent colour, by the drone's affiliation
// (CMBombusHud.Accent: Militech green, Arasaka red and so on).
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
  private let m_fFaction: String;
  private let m_fTexts: array<ref<inkText>>;     // each OSD line, and its shadow beside it
  private let m_fShadows: array<ref<inkText>>;
  private let m_fHorizon: ref<inkCanvas>;
  private let m_fSprite: array<ref<inkImage>>;
  private let m_fRec: ref<inkRectangle>;
  private let m_fBatBar: ref<inkRectangle>;
  private let m_fClock: Float;          // s flown (the OSD timer, the battery's sag)
  private let m_fBlink: Float;
  private let m_fHitT: Float;
  private let m_fBoot: Float;

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

  // the affiliation's accent (Omar: Militech green, Arasaka red, and so on)
  public static func Accent(faction: String) -> HDRColor {
    switch faction {
      case "militech": return new HDRColor(0.34, 1.02, 0.46, 1.0);
      case "arasaka": return new HDRColor(1.18, 0.26, 0.22, 1.0);
      case "kangtao": return new HDRColor(1.10, 0.86, 0.22, 1.0);
      case "ncpd": return new HDRColor(0.30, 0.62, 1.20, 1.0);
      case "aldecaldos": return new HDRColor(1.12, 0.62, 0.26, 1.0);
      case "zetatech": return new HDRColor(0.30, 1.00, 1.10, 1.0);
    }
    return new HDRColor(0.30, 1.00, 1.10, 1.0);
  }

  private func Ink() -> HDRColor = new HDRColor(1.0, 1.0, 1.0, 1.0)
  private func Acc() -> HDRColor = CMBombusHud.Accent(this.m_fFaction)

  public func SetFaction(faction: String) -> Void {
    this.m_fFaction = faction;
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
  }

  // the cheap analog feed: scanlines over everything, the edges darkened
  private func BuildFeed(root: ref<inkCanvas>) -> Void {
    let black = new HDRColor(0.0, 0.0, 0.0, 1.0);
    let y = 0.0;
    while y < 2160.0 {
      CMPilotHud.Bar(root, 0.0, y, this.m_fW, 2.0, black, 0.10);
      y += 7.0;
    }
    let e = 0;
    while e < 4 {
      let d = Cast<Float>(e) * 40.0;
      CMPilotHud.Bar(root, 0.0, d, this.m_fW, 40.0, black, 0.10);
      CMPilotHud.Bar(root, 0.0, 2120.0 - d, this.m_fW, 40.0, black, 0.10);
      CMPilotHud.Bar(root, d, 0.0, 40.0, 2160.0, black, 0.10);
      CMPilotHud.Bar(root, this.m_fW - 40.0 - d, 0.0, 40.0, 2160.0, black, 0.10);
      e += 1;
    }
  }

  // a line of OSD text with its black shadow, at index `i` of m_fTexts
  private func Osd(root: ref<inkCanvas>, x: Float, y: Float, size: Int32, centred: Bool, right: Bool) -> Void {
    let sh = CMPilotHud.Label(root, inkEAnchor.TopLeft, x + 3.0, y + 3.0, "", size, n"Semi-Bold", new HDRColor(0.0, 0.0, 0.0, 1.0));
    let t = CMPilotHud.Label(root, inkEAnchor.TopLeft, x, y, "", size, n"Semi-Bold", this.Ink());
    sh.SetOpacity(0.85);
    if centred {
      sh.SetAnchorPoint(Vector2(0.5, 0.0));
      t.SetAnchorPoint(Vector2(0.5, 0.0));
    }
    if right {
      sh.SetAnchorPoint(Vector2(1.0, 0.0));
      t.SetAnchorPoint(Vector2(1.0, 0.0));
    }
    ArrayPush(this.m_fTexts, t);
    ArrayPush(this.m_fShadows, sh);
  }

  private func SetT(i: Int32, text: String) -> Void {
    if i < ArraySize(this.m_fTexts) {
      this.m_fTexts[i].SetText(text);
      this.m_fShadows[i].SetText(text);
    }
  }

  private func Tint(i: Int32, c: HDRColor) -> Void {
    if i < ArraySize(this.m_fTexts) {
      this.m_fTexts[i].SetTintColor(c);
    }
  }

  private func BuildOsd(root: ref<inkCanvas>) -> Void {
    let W = this.m_fW;
    // in m_fTexts' order (T_*)
    this.Osd(root, 150.0, 120.0, 40, false, false);            // name
    this.Osd(root, 150.0, 172.0, 52, false, false);            // battery
    this.Osd(root, 150.0, 238.0, 36, false, false);            // link
    this.Osd(root, W - 150.0, 120.0, 52, false, true);         // timer
    this.Osd(root, W - 150.0, 186.0, 36, false, true);         // mode
    this.Osd(root, W * 0.5 - 760.0, 1050.0, 48, false, true);  // speed
    this.Osd(root, W * 0.5 + 760.0, 1050.0, 48, false, false); // height
    this.Osd(root, 150.0, 1900.0, 44, false, false);           // throttle
    this.Osd(root, W * 0.5, 1800.0, 46, true, false);          // payload
    this.Osd(root, W * 0.5, 1866.0, 60, true, false);          // ARMED
    this.Osd(root, W * 0.5, 700.0, 54, true, false);           // warnings
    this.Osd(root, W * 0.5, 1950.0, 32, true, false);          // the key hint
    this.Osd(root, W - 210.0, 252.0, 36, false, true);         // REC
    this.Osd(root, W * 0.5 + 760.0, 1110.0, 34, false, false); // vertical speed
    // the battery's bar under it, the recording dot beside REC
    CMPilotHud.Bar(root, 150.0, 236.0, 260.0, 4.0, new HDRColor(0.0, 0.0, 0.0, 1.0), 0.7);
    this.m_fBatBar = CMPilotHud.Bar(root, 150.0, 236.0, 260.0, 4.0, this.Acc(), 1.0);
    this.m_fRec = CMPilotHud.Bar(root, W - 196.0, 262.0, 26.0, 26.0, CMPilotHud.Red(), 1.0);
    // the crosshair: a small -+-, fixed
    let cx = W * 0.5;
    let cy = 1080.0;
    CMPilotHud.Bar(root, cx - 70.0, cy - 2.0, 44.0, 4.0, this.Ink(), 0.95);
    CMPilotHud.Bar(root, cx + 26.0, cy - 2.0, 44.0, 4.0, this.Ink(), 0.95);
    CMPilotHud.Bar(root, cx - 2.0, cy - 14.0, 4.0, 28.0, this.Ink(), 0.95);
    // the horizon: a dashed line that tilts and rides with the drone
    let hz = new inkCanvas();
    hz.SetMargin(inkMargin(cx - 500.0, cy, 0.0, 0.0));
    hz.SetSize(Vector2(1000.0, 6.0));
    hz.SetRenderTransformPivot(Vector2(0.5, 0.5));
    hz.Reparent(root);
    let d = 0;
    while d < 9 {
      if d != 4 {
        CMPilotHud.Bar(hz, Cast<Float>(d) * 112.0, 0.0, 70.0, 5.0, this.Acc(), 0.9);
      }
      d += 1;
    }
    this.m_fHorizon = hz;
    this.SetT(this.T_HINT, "[LMB] DETONATE");
    this.SetT(this.T_REC, "REC");
    this.Tint(this.T_ARM, this.Acc());
    this.Tint(this.T_WARN, CMPilotHud.Red());
  }

  // the Bombus, scanned from its own meshes, bottom right
  private func BuildSprite(root: ref<inkCanvas>) -> Void {
    let k = 300.0 / 360.0;
    let box = new inkCanvas();
    box.SetMargin(inkMargin(this.m_fW - 170.0 - 360.0 * k, 1700.0 - 300.0, 0.0, 0.0));
    box.SetSize(Vector2(360.0 * k, 300.0));
    box.Reparent(root);
    this.Layer(box, k, n"bombus_body", 92.0, 77.0, 177.0, 186.0);
    this.Layer(box, k, n"bombus_arm_l", 5.0, 121.0, 93.0, 115.0);
    this.Layer(box, k, n"bombus_arm_r", 262.0, 121.0, 94.0, 115.0);
    this.Layer(box, k, n"bombus_arm_back", 120.0, 257.0, 121.0, 98.0);
    this.Layer(box, k, n"bombus_payload", 123.0, 5.0, 110.0, 80.0);
  }

  private func Layer(box: ref<inkCanvas>, k: Float, name: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
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

  // ---- each frame / tick -----------------------------------------------------------
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.m_fRoot) {
      return;
    }
    this.SetT(this.T_NAME, s.title);
    this.SetT(this.T_LINK, "RSSI " + IntToString(RoundF(s.signal * 99.0)) + "   LQ " + IntToString(Clamp(RoundF(s.signal * 100.0) + 1, 0, 100)) + "   " + FloatToStringPrec(s.distance / 1000.0, 2) + "KM");
    this.SetT(this.T_THR, "THR " + IntToString(RoundF(s.spool * 100.0)) + "%");
    this.SetT(this.T_PAY, s.priText);
    this.SetT(this.T_ARM, StrLen(s.secText) > 0 ? s.secText : "");
    this.SetT(this.T_MODE, s.terText);
    // the warnings: the link first, then the hull, then anything the drone says
    let warn = s.warning;
    if s.signal < 0.35 {
      warn = "LINK WEAK";
    } else {
      if s.integrity < 0.3 {
        warn = "HULL CRITICAL";
      }
    }
    this.SetT(this.T_WARN, warn);
    // the sprite: the whole drone tinted by the hull
    let hull = ClampF(s.integrity, 0.0, 1.0);
    let c = hull < 0.3 ? CMPilotHud.Red() : (hull < 0.6 ? CMPilotHud.Caution() : this.Acc());
    for img in this.m_fSprite {
      img.SetTintColor(c);
    }
  }

  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.m_fRoot) {
      return;
    }
    this.m_fHorizon.SetRotation(-roll);
    this.m_fHorizon.SetMargin(inkMargin(this.m_fW * 0.5 - 500.0, 1080.0 + ClampF(pitch, -40.0, 40.0) * 12.0, 0.0, 0.0));
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

  // every frame: the timer, a 4S pack sagging as it flies, the REC dot, the boot fade-in
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
    this.SetT(this.T_BAT, "4S  " + FloatToStringPrec(cell * 4.0, 1) + "V");
    let frac = ClampF((cell - 3.3) / 0.9, 0.0, 1.0);
    this.m_fBatBar.SetSize(Vector2(260.0 * frac, 4.0));
    this.m_fBatBar.SetTintColor(frac < 0.25 ? CMPilotHud.Red() : this.Acc());
    this.m_fRec.SetOpacity(this.m_fBlink - Cast<Float>(FloorF(this.m_fBlink)) < 0.5 ? 1.0 : 0.15);
    if this.m_fHitT > 0.0 {
      this.m_fHitT = MaxF(0.0, this.m_fHitT - dt);
      this.m_fHorizon.SetOpacity(this.m_fHitT > 0.0 ? 0.4 : 1.0);
    }
  }

  // a round of ours connected: the horizon flickers, as a cheap feed does
  public func Hit(kill: Bool) -> Void {
    this.m_fHitT = kill ? 0.25 : 0.1;
  }
}
