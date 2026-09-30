// =============================================================================
// CONTROLLABLE MECHS - ROBOT LINK TERMINAL (on TerminalKit's ready-made frame)
// TKPopup gives the lens, brand bar, sidebar tabs, scrolling page, tooltips,
// right-click back and Esc close; CMContent fills the pages. Opened with ]
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
  public func Tabs() -> array<String> = ["UNIT|link", "CONFIG|settings", "TOOLS|tk_tools"]
  public func Brand() -> String = "MILITECH"
  public func Name() -> String = "ROBOT LINK"
  public func Status() -> String = "MT-FCS FIELD TERMINAL // SECURE CH 07 // v" + CMVersion.Text() + " // ] CLOSE"
  public func BootText() -> String = "MILITECH FIELD TERMINAL // AUTHENTICATING OPERATOR..."
  public func BootLines() -> array<String> = ["MILITECH FIELD TERMINAL // COLD START", "OPERATOR AUTHENTICATED", "SECURE CHANNEL 07 ........ UP", "UNIT BUS ................. OK", "FIRE CONTROL ............. STANDBY"]
  public func BootSeconds() -> Float = 1.6
  public func StartPage() -> String = "link"
  // the kit's own sizes and texts, whatever another mod's UI tuner plugged into the shared slot
  public func ScaleSource() -> ref<TKScaleSource> = new TKScaleDefaults()

  // the rugged military look (TerminalKit's style hooks): an armoured frame with rivets
  // and hazard blocks, headings on plates, ten-cell bars, faint scanlines
  public func Style() -> ref<TKStyle> {
    let s = new TKStyle();
    s.frame = 2;
    s.rivets = true;
    s.hazard = true;
    s.scanlines = 0.08;
    s.headerPlates = true;
    s.segmentedBars = 10;
    s.selectSound = n"ui_menu_onpress";
    s.denySound = n"ui_hacking_press_fail";
    // Industry: the game's condensed industrial face; it has the one style, Demi
    s.fontFamily = "base\\gameplay\\gui\\fonts\\industry\\industry.inkfontfamily";
    s.fontStyle = n"Demi";
    return s;
  }

  // Forget the open terminal as it closes. Closing() runs before the popup is torn
  // down (Closed() runs after, when GetGame() may no longer resolve, which left the
  // terminal "open" and made the next key press close nothing instead of opening).
  protected func Closing() -> Void {
    CMTerminalState.Forget(this);
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
      }
      return;
    }
    // a remembered terminal that isn't really up any more (closed by a path that
    // skipped our hooks) must not block opening a new one
    state.open = null;
    // available in combat too: only menus, pause and photo mode block it (TKPopup.CanOpen)
    if !TKPopup.CanOpen(player) {
      return;
    }
    TKTheme.Register(new CMMilitaryPalette());   // the same id replaces, so this is safe to repeat
    let terminal = new CMTerminal();
    state.open = terminal;
    TKPopup.Open(player, terminal);
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
    }
    if IsDefined(state) {
      state.open = null;
    }
  }
}

// The terminal's palette, matching the pilot HUD: phosphor olive, amber for emphasis,
// sand text, dark olive rules. Registered with TerminalKit as "cm_military".
public class CMMilitaryPalette extends TKPalette {
  public func Id() -> String = "cm_military"
  public func Color(role: String) -> HDRColor {
    switch role {
      case "title": return new HDRColor(0.58, 0.84, 0.36, 1.0);
      case "accent": return new HDRColor(1.0, 0.70, 0.10, 1.0);
      case "text": return new HDRColor(0.72, 0.78, 0.62, 1.0);
      case "rule": return new HDRColor(0.22, 0.34, 0.15, 1.0);
      case "frame": return new HDRColor(0.46, 0.68, 0.30, 1.0);
    }
    return new HDRColor(0.86, 0.90, 0.76, 1.0);
  }
}

// Which terminal is open (one at a time)
public class CMTerminalState extends ScriptableSystem {
  public let open: wref<CMTerminal>;

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    TKTheme.Register(new CMMilitaryPalette());
  }

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
