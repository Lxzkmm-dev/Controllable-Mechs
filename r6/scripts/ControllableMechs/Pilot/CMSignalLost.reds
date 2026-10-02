// =============================================================================
// MECHS OF NIGHT CITY - SIGNAL LOST (0.7.1-a47)
//
// When a drone is destroyed (the Bombus going off too), its feed dies on screen for a
// moment before the view goes back to V (Omar): the feed flashes, cuts to black and static,
// SIGNAL LOST over it, the drone's name and LINK TERMINATED under it, PRESS [the pilot key]
// blinking at the bottom. CMCSession holds it until that key ends the link (a56, Omar).
// Drawn on the HUD layer over everything, on the same 2160-high design space as the HUDs.
// =============================================================================
module ControllableMechs

import Codeware.UI.ScreenHelper

public class CMSignalLost {
  private let m_root: ref<inkCanvas>;
  private let m_parent: wref<inkCompoundWidget>;
  private let m_flash: ref<inkRectangle>;
  private let m_static: array<ref<inkRectangle>>;
  private let m_title: ref<inkText>;
  private let m_foot: ref<inkText>;
  private let m_t: Float;
  private let m_W: Float;
  private let m_snowMax: Float;         // the brightest a band of static gets

  public static func SignalLostTime() -> Float = 1.5

  // each drone's feed dies in its own display's look (Omar, a48): the Bombus a cheap
  // analogue feed snowing out, white OSD letters; the Octant the MQ-1's green, its C2
  // datalink lost; the Wyvern its ISR feed's teal, the recording stopped; the Griffin its
  // hunter's green with the words in red
  public static func Show(name: String, kind: String) -> ref<CMSignalLost> {
    let s = new CMSignalLost();
    s.Build(name, kind);
    return s;
  }

  private func Build(name: String, kind: String) -> Void {
    let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
    if !IsDefined(layer) {
      return;
    }
    let window = layer.GetVirtualWindow();
    if !IsDefined(window) {
      return;
    }
    this.m_parent = window;
    let root = new inkCanvas();
    root.SetName(n"cm_signal_lost");
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
    this.m_root = root;
    let W = this.m_W;
    let black = new HDRColor(0.0, 0.0, 0.0, 1.0);
    let white = new HDRColor(1.0, 1.0, 1.0, 1.0);
    // the look: the title's colour, the rule's, the static's, how dark the feed goes, how
    // much static, the lines under the title
    let title = CMPilotHud.Red();
    let rule = CMPilotHud.Red();
    let snow = white;
    let dark = 0.94;
    let bands = 48;
    this.m_snowMax = 0.22;
    let sub = name + "   //   LINK TERMINATED";
    // it stays until the pilot key ends the link (a56, Omar), and says so
    let back = "PRESS [" + CMKeys.PilotName(GetPlayer(GetGameInstance())) + "] TO RETURN TO OPERATOR";
    let foot = back;
    switch kind {
      case "bombus":
        // a cheap analogue feed: it snows out, grey, the OSD's white letters
        title = white;
        rule = white;
        snow = new HDRColor(0.85, 0.85, 0.85, 1.0);
        dark = 0.55;
        bands = 140;
        this.m_snowMax = 0.55;
        sub = name + "   //   RSSI 0   LQ 0   //   VTX LOST";
        foot = "NO VIDEO   //   " + back;
        break;
      case "octant":
        title = CMPilotHud.Amber();
        rule = CMPilotHud.Amber();
        snow = CMPilotHud.Amber();
        dark = 0.85;
        bands = 36;
        this.m_snowMax = 0.18;
        sub = name + "   //   C2 DATALINK LOST";
        foot = "LOST LINK PROCEDURE   //   " + back;
        break;
      case "wyvern":
        title = new HDRColor(0.62, 1.05, 1.00, 1.0);
        rule = CMPilotHud.Caution();
        snow = new HDRColor(0.62, 1.05, 1.00, 1.0);
        dark = 0.88;
        bands = 40;
        this.m_snowMax = 0.18;
        sub = name + "   //   ISR FEED TERMINATED   //   REC STOPPED";
        foot = "CONTACTS NOT RETAINED   //   " + back;
        break;
      case "griffin":
        title = CMPilotHud.Red();
        rule = new HDRColor(0.40, 1.05, 0.52, 1.0);
        snow = new HDRColor(0.40, 1.05, 0.52, 1.0);
        dark = 0.9;
        bands = 44;
        this.m_snowMax = 0.2;
        sub = name + "   //   AIRFRAME LOST   //   WEAPONS SAFE";
        foot = back;
        break;
    }
    CMPilotHud.Bar(root, 0.0, 0.0, W, 2160.0, black, dark);
    // static: thin bright bands, moved every frame
    let i = 0;
    while i < bands {
      ArrayPush(this.m_static, CMPilotHud.Bar(root, 0.0, 0.0, W, 4.0, snow, 0.1));
      i += 1;
    }
    // the words
    let cx = W * 0.5;
    let sh = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx + 6.0, 846.0, "SIGNAL LOST", 170, n"Semi-Bold", black);
    sh.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_title = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx, 840.0, "SIGNAL LOST", 170, n"Semi-Bold", title);
    this.m_title.SetAnchorPoint(Vector2(0.5, 0.0));
    let st = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx, 1060.0, sub, 48, n"Semi-Bold", white);
    st.SetAnchorPoint(Vector2(0.5, 0.0));
    st.SetOpacity(0.85);
    CMKit.Pill(root, cx - 700.0, 1038.0, 1400.0, 6.0, rule, 0.9);
    this.m_foot = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx, 1180.0, foot, 36, n"Medium", white);
    this.m_foot.SetAnchorPoint(Vector2(0.5, 0.0));
    // the feed's last flash
    this.m_flash = CMPilotHud.Bar(root, 0.0, 0.0, W, 2160.0, white, 0.9);
    this.Tick(0.0);
  }

  // every frame: the flash fades, the static moves, the title flickers, the footer blinks
  public func Tick(dt: Float) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    this.m_t += dt;
    this.m_flash.SetOpacity(MaxF(0.0, 0.9 - this.m_t * 6.0));
    for b in this.m_static {
      b.SetMargin(inkMargin(0.0, RandRangeF(0.0, 2160.0), 0.0, 0.0));
      b.SetSize(Vector2(this.m_W, RandRangeF(2.0, 14.0)));
      b.SetOpacity(RandRangeF(0.03, this.m_snowMax));
    }
    this.m_title.SetOpacity(RandRangeF(0.0, 1.0) < 0.12 ? 0.35 : 1.0);
    let ph = this.m_t * 3.0;
    this.m_foot.SetOpacity(ph - Cast<Float>(FloorF(ph)) < 0.5 ? 0.9 : 0.25);
  }

  public func Remove() -> Void {
    if IsDefined(this.m_root) && IsDefined(this.m_parent) {
      this.m_parent.RemoveChild(this.m_root);
    }
    this.m_root = null;
    ArrayClear(this.m_static);
  }
}
