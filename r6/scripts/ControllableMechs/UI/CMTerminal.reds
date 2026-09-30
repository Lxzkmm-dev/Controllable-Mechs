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
  public func Tabs() -> array<String> = ["LINK|link", "SETTINGS|settings", "TOOLS|tk_tools"]
  public func Brand() -> String = "MILITECH"
  public func Name() -> String = "ROBOT LINK"
  public func Status() -> String = "NEURAL UPLINK // v" + CMVersion.Text() + " // K TO CLOSE"
  public func BootText() -> String = "ESTABLISHING UPLINK..."
  public func StartPage() -> String = "link"

  protected func Closed() -> Void {
    let state = CMTerminalState.Get(this.GetGame());
    if IsDefined(state) {
      state.open = null;
    }
  }

  public static func Toggle(player: ref<PlayerPuppet>) -> Void {
    if !IsDefined(player) {
      return;
    }
    let state = CMTerminalState.Get(player.GetGame());
    if IsDefined(state.open) && state.open.IsInitialized() {
      if !state.open.IsTyping() {
        state.open.Close();
      }
      return;
    }
    // available in combat too: only menus, pause and photo mode block it (TKPopup.CanOpen)
    if !TKPopup.CanOpen(player) {
      return;
    }
    let terminal = new CMTerminal();
    state.open = terminal;
    TKPopup.Open(player, terminal);
  }

  // closes the terminal if it is up (the Pilot button uses this)
  public static func CloseOpen(game: GameInstance) -> Void {
    let state = CMTerminalState.Get(game);
    if IsDefined(state) && IsDefined(state.open) && state.open.IsInitialized() {
      state.open.Close();
    }
  }
}

// Which terminal is open (one at a time)
public class CMTerminalState extends ScriptableSystem {
  public let open: wref<CMTerminal>;

  public static func Get(game: GameInstance) -> ref<CMTerminalState> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMTerminalState") as CMTerminalState;
  }
}
