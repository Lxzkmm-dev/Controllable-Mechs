// =============================================================================
// MECHS OF NIGHT CITY - SIGNAL LOST (0.7.1-a47)
//
// When a drone is destroyed (the Bombus going off too), its feed dies on screen for a
// moment before the view goes back to V (Omar): the feed flashes, cuts to black and static,
// SIGNAL LOST over it, the drone's name and LINK TERMINATED under it, RETURNING TO OPERATOR
// blinking at the bottom. CMCSession holds it SignalLostTime() and then ends the link.
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

  public static func SignalLostTime() -> Float = 1.5

  public static func Show(name: String) -> ref<CMSignalLost> {
    let s = new CMSignalLost();
    s.Build(name);
    return s;
  }

  private func Build(name: String) -> Void {
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
    let red = CMPilotHud.Red();
    CMPilotHud.Bar(root, 0.0, 0.0, W, 2160.0, black, 0.94);
    // static: thin bright bands, moved every frame
    let i = 0;
    while i < 48 {
      ArrayPush(this.m_static, CMPilotHud.Bar(root, 0.0, 0.0, W, 4.0, white, 0.1));
      i += 1;
    }
    // the words
    let cx = W * 0.5;
    let sh = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx + 6.0, 846.0, "SIGNAL LOST", 170, n"Semi-Bold", black);
    sh.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_title = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx, 840.0, "SIGNAL LOST", 170, n"Semi-Bold", red);
    this.m_title.SetAnchorPoint(Vector2(0.5, 0.0));
    let sub = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx, 1060.0, name + "   //   LINK TERMINATED", 48, n"Semi-Bold", white);
    sub.SetAnchorPoint(Vector2(0.5, 0.0));
    sub.SetOpacity(0.85);
    CMPilotHud.Bar(root, cx - 700.0, 1040.0, 1400.0, 4.0, red, 0.9);
    this.m_foot = CMPilotHud.Label(root, inkEAnchor.TopLeft, cx, 1180.0, "RETURNING TO OPERATOR", 36, n"Medium", white);
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
      b.SetOpacity(RandRangeF(0.03, 0.22));
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
