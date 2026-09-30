// =============================================================================
// CONTROLLABLE MECHS - ROBOT LINK TERMINAL (on TerminalKit's ready-made frame)
// TKPopup gives the lens, brand bar, sidebar tabs, scrolling page, tooltips,
// right-click back and Esc close; CMContent fills the pages. Opened with K
// (CM_OpenLink, Input Loader) through CMTerminal.Toggle. Works in combat; not over
// a menu. TerminalKit comes from the TerminalKIT mod (a requirement).
// =============================================================================
module ControllableMechs

import TerminalKit.*

public class CMTerminal extends TKPopup {
  public func Content() -> ref<TKContent> {
    let c = new CMContent();
    c.game = this.GetGame();
    return c;
  }
  public func Tabs() -> array<String> = ["LINK|link", "SETTINGS|settings", "SPIKES|spikes", "TOOLS|tk_tools"]
  public func Brand() -> String = "MILITECH"
  public func Name() -> String = "ROBOT LINK"
  public func Status() -> String = "NEURAL UPLINK // v" + CMVersion.Text() + " // ] TO CLOSE"
  public func BootText() -> String = "ESTABLISHING UPLINK..."
  public func StartPage() -> String = "link"

  // Forget the open terminal as it closes. Closing() runs before the popup is torn
  // down (Closed() runs after, when GetGame() may no longer resolve, which left the
  // terminal "open" and made the next key press close nothing instead of opening).
  protected func Closing() -> Void {
    CMTerminalState.Forget(this);
    TKLog.Add("ControllableMechs", "terminal: closing");
  }

  protected func Closed() -> Void {
    CMTerminalState.Forget(this);
  }

  public static func Toggle(player: ref<PlayerPuppet>) -> Void {
    if !IsDefined(player) {
      return;
    }
    let state = CMTerminalState.Get(player.GetGame());
    if CMTerminal.IsUp(state) {
      if !state.open.IsTyping() {
        state.open.Close();
        TKLog.Add("ControllableMechs", "terminal: closed by key");
      }
      return;
    }
    // a remembered terminal that isn't really up any more (closed by a path that
    // skipped our hooks) must not block opening a new one
    state.open = null;
    // available in combat too: only menus, pause and photo mode block it (TKPopup.CanOpen)
    if !TKPopup.CanOpen(player) {
      TKLog.Add("ControllableMechs", "terminal: not opened (a menu, pause or photo mode is up)");
      return;
    }
    let terminal = new CMTerminal();
    state.open = terminal;
    TKPopup.Open(player, terminal);
    TKLog.Add("ControllableMechs", "terminal: opened");
  }

  // really on screen: remembered, initialised, and its root widget exists and is visible
  public static func IsUp(state: ref<CMTerminalState>) -> Bool {
    if !IsDefined(state) || !IsDefined(state.open) || !state.open.IsInitialized() {
      return false;
    }
    let root = state.open.GetRootWidget();
    return IsDefined(root) && root.IsVisible();
  }

  // closes the terminal if it is up (the Pilot button uses this)
  public static func CloseOpen(game: GameInstance) -> Void {
    let state = CMTerminalState.Get(game);
    if CMTerminal.IsUp(state) {
      state.open.Close();
      TKLog.Add("ControllableMechs", "terminal: closed by a button (pilot / spike)");
    }
    if IsDefined(state) {
      state.open = null;
    }
  }
}

// Which terminal is open (one at a time)
public class CMTerminalState extends ScriptableSystem {
  public let open: wref<CMTerminal>;

  public static func Get(game: GameInstance) -> ref<CMTerminalState> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMTerminalState") as CMTerminalState;
  }

  // the global game instance: it resolves even while a popup is being torn down
  public static func Forget(terminal: ref<CMTerminal>) -> Void {
    let state = CMTerminalState.Get(GetGameInstance());
    if IsDefined(state) && state.open == terminal {
      state.open = null;
    }
  }
}
