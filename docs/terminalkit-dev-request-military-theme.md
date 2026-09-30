# TerminalKit dev request: a rugged military theme a mod can supply

**From:** Controllable Mechs (2026-09-30)
**Why:** Omar wants the mod's UI "much much more rugged and military". The pilot HUD is ours and has been restyled (`CMPilotHud.reds`: olive palette, steel plates, rivets, hazard stripes, segmented bars, scanlines, boot sequence). The Robot Link terminal is a `TKPopup`, and its look (palette, font, frame, bars, sounds) is TerminalKit's. We can only change the words. This asks for hooks so a mod can supply a look without TerminalKit knowing the mod.

Everything below is optional per popup and defaults to today's behaviour, so existing terminals (Night City Empires, Tools) don't change.

## What TerminalKit has today (read from the source, 2026-09-30)

- `TKTheme.Ids()` is a fixed list (`hud, kiroshi, arasaka, militech, netwatch, mono`) and `TKTheme.Color(theme, role)` is a `switch` over it. Roles: `title, accent, text, value (default), frame, rule`. A mod can pick a theme (`TKPage.SetTheme`) but can't add one.
- `TKInk.Font(t, size, weight)` sets the one font family for all text.
- The frame chrome (lens, brand bar, sidebar, corner marks) is built inside `TKPopup` / `TKView` with no hook.
- `TKPage.Stat(..., fraction)` and `TKInk.Meter` draw a smooth bar.
- `TKScale` / `TKTools` take one global source each (the earlier request `docs/terminalkit-dev-request.md` covers that).

## Requested hooks

### 1. A mod-supplied palette

```redscript
// TKTheme.reds
public abstract class TKPalette extends IScriptable {
  public func Id() -> String                    // e.g. "cm_military"
  public func Color(role: String) -> HDRColor   // title, accent, text, value, frame, rule
}

public abstract class TKTheme {
  public static func Register(palette: ref<TKPalette>) -> Void   // keyed by Id(); re-registering replaces
  public static func Ids() -> array<String>                      // built-ins, then registered ids
  public static func Color(theme: String, role: String) -> HDRColor   // looks up registered palettes first
}
```

Storage: a `TKThemeSystem` ScriptableSystem holding `array<ref<TKPalette>>`, like `TKLogSystem`. `Paint` / `PaintNew` / `Fix` already route through `Color`, so nothing else changes.

Controllable Mechs would register one palette on player attach: phosphor olive `(0.58, 0.84, 0.36)` title and value, amber `(1.0, 0.70, 0.10)` accent, sand `(0.86, 0.90, 0.76)` text, dark olive `(0.30, 0.44, 0.20)` rule and frame.

### 2. A style object per popup

```redscript
// TKPopup.reds
public class TKStyle extends IScriptable {
  public let fontFamily: String;      // "" = today's font
  public let titleWeight: CName;      // n"" = today's
  public let bodyWeight: CName;
  public let upperCase: Bool;         // force upper case on headings and buttons
  public let frame: Int32;            // TKFrame: 0 Default, 1 Notched, 2 Armoured
  public let rivets: Bool;            // a rivet row along the brand bar and the footer
  public let hazard: Bool;            // hazard-stripe blocks in the frame's corners
  public let headerPlates: Bool;      // Heading rows drawn as a dark plate with an edge bar
  public let segmentedBars: Int32;    // 0 = smooth (today); N = Stat / Meter drawn as N segments
  public let scanlines: Float;        // 0 = none; opacity of a static scanline overlay
  public let openSound: CName;        // played on the player when the popup opens
  public let closeSound: CName;
  public let selectSound: CName;      // button / tab press
  public let denySound: CName;        // a disabled button pressed
}

public class TKPopup {
  public func Style() -> ref<TKStyle> = null   // null = today's look
}
```

Where it would be read:
- **Font and case:** `TKInk.Font` takes the family from the style when set. The simplest route is `TKView` keeping `m_style` and passing it down, as it does `m_theme`.
- **Frame:** the chrome builder in `TKPopup` switches on `frame`. `Notched` cuts the four corners at 45 degrees (rotated rectangles over the corners, in the `Ink()` colour). `Armoured` adds a second inner border line and thicker corner brackets.
- **Rivets, hazard, scanlines:** static rectangles added once when the chrome is built, in the `frame` / `rule` roles (hazard stripes in `accent`). Never touched again.
- **Header plates:** `TKRows.Heading` draws a `TKInk.Rect` plate and a 9 px edge bar behind the text when set.
- **Segmented bars:** `TKInk.Meter` overlays `N - 1` dividers in the `Ink()` colour. The fill stays one rectangle, so it costs nothing per update.
- **Sounds:** `GameObject.PlaySoundEvent(player, name)` at open, close, `OnActClick` / tab click, and a disabled press. `n""` plays nothing.

Controllable Mechs would return: `frame = Armoured, rivets, hazard, headerPlates, segmentedBars = 10, scanlines = 0.08, upperCase`, and the game sounds it already uses on the HUD.

### 3. A boot hook (optional)

`TKPopup.BootText()` is one line today. For a military boot:

```redscript
public func BootLines() -> array<String> = []   // empty = BootText() as today
public func BootSeconds() -> Float = 0.0        // 0 = today's timing
```

Lines appear one at a time over `BootSeconds()`.

## Compatibility

- Every hook has a default equal to today's behaviour; no existing provider needs a change.
- Palettes are looked up by id, so a save that stored a registered theme's id falls back to the default colour if the mod is removed (`Color`'s existing `default` branch).
- Cost: the style is read when the chrome and rows are built. Nothing new per frame.

## What we do meanwhile

Wording only: tabs UNIT / CONFIG, a field-terminal status line and boot text, UNIT CONTROL, PILOT INTERFACE, UNIT ORDERS, CONFIGURATION (`CMContent.reds`, `CMTerminal.reds`), on TerminalKit's own `militech` palette.
