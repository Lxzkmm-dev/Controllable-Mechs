# TerminalKit

A page engine for in-game terminals, written in redscript. It draws pages described as data (rows) inside any frame you build, with the game's own fonts, buttons and colours. Night City Empires' Fixer Link runs on it; it knows nothing about that mod, so it can be dropped into another one.

Needs **Codeware** (buttons, text boxes, the popup base) and **RedFunctions** (the mouse state). Copy `r6/scripts/TerminalKit` into your mod and `import TerminalKit.*`.

## The pieces

- **TKPage** (`TKPage.reds`): a page is a title, a subtitle, a status message and a list of `TKRow`s. Builders: `Heading`, `Text`, `Pair`, `Meter`, `Button`, `Note`, `Gap`, `Item` (text, value, a button), `Levels` (an item with a level track), `Buttons` (several buttons on a row), `Links` (a tab row), `Slider`, `Track` (a meter with named marks), `Section` (collapsible), `Input` (a text box), `Entry` (a feed entry), `Dossier`, `Columns`, `Ledger` (a table line), `Board` (a departures-board line), `Card`, `Stat`, `Ticker`, `Tile`, `Column` / `EndColumns` (side-by-side layout), `Custom` (a row your provider draws itself).
  - Action rows split their buttons once, typed: `row.labels`, `row.actions`, `row.args`. String builders take `"A|B"` labels, `"a|b"` actions and `"x|y"` args (or `"x\ny"` when an arg holds `|`); `Actions(...)` takes arrays. A row with one action keeps its whole arg.
  - Marks in text: a leading `!` shows red, `*` green (neither is shown), `+` amounts green; on boards `^` bright yellow and `~` grey.
- **TKContent** (`TKPage.reds`): what the kit asks of your mod. Subclass it: `Request(page, name, arg)` fills the page, `Act(page, action, arg)` runs a button (set `page.GoTo`, `page.SetMessage`, `page.rebuild` or `page.skipRedraw`), `Custom(...)` draws a custom row and returns a `TKCustom` the view stops when the page goes, `Rebuild()` rebuilds your frame when the layout changed.
- **TKView** (`TKView.reds`): the renderer. Your frame gives it a content panel, a title, a subtitle and a message line (`Bind`), optionally a scroll area (`BindScroll`), your `TKContent` (`SetContent`) and a `TKFrame` (`SetFrame`: the input owner and a way to hide the frame around a bare page). `Show(page, arg, message)` draws a page; `AddTab` adds sidebar tabs; `Chrome` registers frame pieces that follow the palette. The mouse wheel scrolls when your frame forwards its global relative input to `OnWheel`.
- **TKRows / TKTables / TKTiles**: the components, one static draw function per row kind, all drawing through the view's helpers (`Text`, `RowBox`, `ActButton`, `GridCell`, `Panel`, `Frame`, `Rule`...). Add a kind by adding a builder to `TKPage`, a case to `TKView.Draw` and a draw function.
- **TKTheme** (`TKTheme.reds`): palettes by role (`title`, `accent`, `text`, `value`, `frame`, `rule`); `hud` follows the game's own UI colours. `Tone` maps row colour names; `Gain` / `Loss` / `Amber` / `Gold` are the status colours.
- **TKScale**: layout numbers by key with defaults, and the tokens (five type sizes, four spacings). Plug a `TKScaleSource` in with `TKScale.Use(...)` to feed values (a tuner, a settings file) and text replacements.
- **TKInk**: small widget builders (text, strips, meters, rectangles, lines).
- **TKButton**: a vanilla-style button sized for a page; **TKSlider**: a slider's live state.

## A minimal frame

```
let view = new TKView();
view.SetContent(new MyContent());        // extends TKContent
view.AddTab(sidebar, "HOME", "home", 460.0, 74.0, 30);
view.Bind(contentPanel, titleText, subtitleText, messageText, 2300.0);
view.BindScroll(scrollArea, 1080.0, trackRect, barRect);   // optional
view.Show("home", "", "");
```

Forward your popup's `OnPostOnRelative` global input to `view.OnWheel(e)` for scrolling, and call `view.StopCustom()` when the frame closes.

## Conventions

- The canvas is 4K-sized and shrunk to the screen: 3000 × 1500 for a full-screen frame, with a 2300-wide page. Type sizes below 24 get two points added so labels stay crisp at 1440p.
- Ink blends premultiplied in linear light: colours brighter than white bloom, so `TKTheme.C` caps at white.
- Only unbind a style binding that exists; `Paint` handles that (unbinding on a fresh widget crashed the game).
