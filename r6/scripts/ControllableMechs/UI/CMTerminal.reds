// =============================================================================
// CONTROLLABLE MECHS - ROBOT LINK TERMINAL (the TerminalKit frame)
// A Codeware popup over the world: brand bar,
// tabs on the left, the page on the right. TerminalKit draws the pages from
// CMContent. Opened with K (CM_OpenLink, Input Loader) or CMTerminal.Toggle.
// Not available in combat or over a menu.
// =============================================================================
module ControllableMechs

import Codeware.UI.*
import TerminalKit.*

public class CMTerminal extends InGamePopup {
  protected let m_player: wref<PlayerPuppet>;
  protected let m_view: ref<TKView>;
  protected let m_frame: wref<inkCompoundWidget>;

  private let WIDTH: Float = 3000.0;
  private let HEIGHT: Float = 1500.0;
  private let CONTENT: Float = 2300.0;

  public static func Toggle(player: ref<PlayerPuppet>) -> Void {
    if !IsDefined(player) {
      return;
    }
    let state = CMTerminalState.Get(player.GetGame());
    if IsDefined(state.open) && state.open.IsInitialized() {
      if state.open.IsTyping() {
        return;
      }
      state.open.Close();
      return;
    }
    if !CMTerminal.CanOpen(player) {
      return;
    }
    if player.IsInCombat() {
      player.SetWarningMessage("ROBOT LINK UNAVAILABLE IN COMBAT");
      return;
    }
    let terminal = new CMTerminal();
    terminal.m_player = player;
    state.open = terminal;
    GameInstance.GetUISystem(player.GetGame()).QueueEvent(ShowCustomPopupEvent.Create(terminal));
  }

  // Only from plain gameplay: a popup queued under a menu locks the controls
  public static func CanOpen(player: ref<PlayerPuppet>) -> Bool {
    let game = player.GetGame();
    let ui = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UI_System);
    if IsDefined(ui) && ui.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu) {
      return false;
    }
    if GameInstance.GetTimeSystem(game).IsPausedState() {
      return false;
    }
    return !GameInstance.GetPhotoModeSystem(game).IsPhotoModeActive();
  }

  public func UseCursor() -> Bool = true

  public func IsTyping() -> Bool = IsDefined(this.m_view) && this.m_view.IsTyping()

  protected func SetUIContext() -> Void {
    GameInstance.GetUISystem(this.GetGame()).PushGameContext(UIGameContext.ModalPopup);
  }

  protected func ResetUIContext() -> Void {
    GameInstance.GetUISystem(this.GetGame()).PopGameContext(UIGameContext.ModalPopup);
  }

  protected func CreateContainer() -> Void {
    let frame = new inkCanvas();
    frame.SetName(n"container");
    frame.SetAnchor(inkEAnchor.Centered);
    frame.SetAnchorPoint(Vector2(0.5, 0.5));
    frame.SetSize(Vector2(this.WIDTH, this.HEIGHT));
    frame.Reparent(this.GetRootCompoundWidget());
    this.m_container = frame;
    this.m_frame = frame;
    this.SetContainerWidget(frame);
  }

  protected cb func OnCreate() -> Void {
    super.OnCreate();
    this.BuildFrame();
    this.RegisterToGlobalInputCallback(n"OnPostOnRelative", this, n"OnWheel");
    this.RegisterToGlobalInputCallback(n"OnPostOnRelease", this, n"OnRelease");
    this.m_view.Show("link", "", "");
  }

  private func BuildFrame() -> Void {
    let frame = this.m_frame;
    let content = new CMContent();
    content.game = this.GetGame();
    let owner = new CMFrame();
    owner.popup = this;
    this.m_view = new TKView();
    this.m_view.SetContent(content);
    this.m_view.SetFrame(owner);

    // top bar
    let brand = TKInk.Plain(frame, "CONTROLLABLE MECHS  //  ROBOT LINK", TKScale.TypeXL(), n"Semi-Bold", 0.0);
    brand.SetMargin(inkMargin(70.0, 40.0, 0.0, 0.0));
    this.m_view.Chrome(brand, "accent");
    let rule = new inkRectangle();
    rule.SetSize(Vector2(this.WIDTH - 140.0, 2.0));
    rule.SetMargin(inkMargin(70.0, 150.0, 0.0, 0.0));
    rule.Reparent(frame);
    this.m_view.Chrome(rule, "rule");

    // body: tabs left, page right
    let body = new inkHorizontalPanel();
    body.SetMargin(inkMargin(70.0, 190.0, 0.0, 0.0));
    body.Reparent(frame);
    let side = new inkVerticalPanel();
    side.SetMargin(inkMargin(0.0, 0.0, 80.0, 0.0));
    side.Reparent(body);
    this.m_view.AddTab(side, "LINK", "link", 460.0, 74.0, 30).GetRootWidget().SetMargin(inkMargin(0.0, 0.0, 0.0, 12.0));
    this.m_view.AddTab(side, "SETTINGS", "settings", 460.0, 74.0, 30);

    let page = new inkVerticalPanel();
    page.Reparent(body);
    let title = TKInk.Plain(page, "", 56, n"Medium", 0.0);
    this.m_view.Chrome(title, "title");
    let subtitle = TKInk.Plain(page, "", 28, n"Regular", 2.0);
    this.m_view.Chrome(subtitle, "text");
    let panel = new inkVerticalPanel();
    panel.SetMargin(inkMargin(0.0, 12.0, 0.0, 0.0));
    panel.Reparent(page);
    let message = TKInk.Plain(page, "", 30, n"Medium", 20.0);
    this.m_view.Chrome(message, "value");
    this.m_view.Bind(panel, title, subtitle, message, this.CONTENT);

    let foot = TKInk.Plain(frame, "[ESC] CLOSE   [RMB] BACK", 26, n"Medium", 0.0);
    foot.SetAnchor(inkEAnchor.BottomLeft);
    foot.SetAnchorPoint(Vector2(0.0, 1.0));
    foot.SetMargin(inkMargin(70.0, 0.0, 0.0, 40.0));
    this.m_view.Chrome(foot, "text");
  }

  protected cb func OnWheel(e: ref<inkPointerEvent>) -> Bool {
    return this.m_view.OnWheel(e);
  }

  protected cb func OnRelease(e: ref<inkPointerEvent>) -> Bool {
    if e.IsAction(n"mouse_right") {
      this.m_view.Back();
    }
    return false;
  }

  protected cb func OnHidden() -> Void {
    this.UnregisterFromGlobalInputCallback(n"OnPostOnRelative", this, n"OnWheel");
    this.UnregisterFromGlobalInputCallback(n"OnPostOnRelease", this, n"OnRelease");
    this.m_view.StopCustom();
    let state = CMTerminalState.Get(this.GetGame());
    if IsDefined(state) {
      state.open = null;
    }
    super.OnHidden();
  }
}

// TerminalKit's handle on the frame (the owner of global input)
public class CMFrame extends TKFrame {
  public let popup: wref<CMTerminal>;
  public func Owner() -> ref<inkCustomController> = this.popup
}

// Which terminal is open (one at a time)
public class CMTerminalState extends ScriptableSystem {
  public let open: wref<CMTerminal>;

  public static func Get(game: GameInstance) -> ref<CMTerminalState> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMTerminalState") as CMTerminalState;
  }
}
