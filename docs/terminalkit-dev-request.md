# TerminalKit dev request: per-terminal scale source and Tools host

From Controllable Mechs (2026-09-30). This asks for a change to TerminalKit, and Controllable Mechs does not modify TerminalKit itself.

## The problem

TerminalKit keeps two settings as single global slots. The first mod to install one sets it for every terminal of every mod.

1. **The layout and text source.** `TKScale.Use(source)` stores one `TKScaleSource` in `TKScaleSystem.source` (`TKTheme.reds`). `TKScale.F` / `I` / `T` read that slot everywhere:
   - `TKPopup` sizes: `frame.w`, `frame.name`, `frame.brand`, `content.w`, and so on;
   - `TKPopup` texts: `Brand()`, `Name()`, `Status()`, `Footer()` and `BootText()` all pass through `TKScale.T`;
   - `TKView` page titles, subtitles and messages;
   - button labels (`TKButton.Make`) and the type and space tokens.
2. **The Tools host.** `TKTools.Use(host)` stores one `TKToolsHost` in `TKToolsSystem.host`, which sets the storage folder, the kinds and sizes, and the district.

Night City Empires installs `NCEScaleSource` (its UI Tuner, backed by `ui_layout.json`) and `NCEToolsHost` into those slots (`NCEFixerSite.reds`). With both mods loaded:

- **UI Tuner leaks:** every NCE UI Tuner size or text replacement also applies to Controllable Mechs' Robot Link, for example a tuned `frame.name` size or a replaced title text. It's latent today because Omar's setup has no `ui_layout.json`, but it fires as soon as the tuner is used.
- **Tools storage:** the Robot Link's TOOLS tab reads and writes NCE's storage (`r6/storages/NightCityEmpires`), and NCE's `Changed()` hooks run when positions are logged from Controllable Mechs.
- **Load-order behaviour:** whichever mod installs first wins, and `NCEScaleSource.Install()` only installs when the slot is empty.

## What would fix it

Let a terminal carry its own source and host, and fall back to the global slots only when it doesn't:

```
// TKPopup: optional per-terminal overrides (null = use the global slot, as today)
public func ScaleSource() -> ref<TKScaleSource> = null
public func ToolsHost() -> ref<TKToolsHost> = null
```

- **Scale source:** `TKPopup` / `TKView` would resolve their scale source once at build time (`this.ScaleSource()`, else `TKScaleSystem.source`, else the defaults) and use it for every `F` / `I` / `T` call made while drawing that terminal. One way is to pass it into the view (`TKView.SetScale(source)`) and have `TKView` / `TKRows` / `TKButton` read `v.Scale()` instead of the static `TKScale`. The static `TKScale` can stay for code outside a view.
- **Tools host:** the same for `TKTools.Request` / `Act`, which would take the view's host (`TKView.ToolsHost()`), else the global slot.
- **Compatibility:** mods that override nothing behave exactly as today. NCE would override `ScaleSource()` / `ToolsHost()` in `NCEOpticsTerminal` (and its Fixer Net frame) instead of calling `TKScale.Use` / `TKTools.Use` globally. Controllable Mechs would return a plain `TKScaleSource` (defaults) and its own `TKToolsHost` (storage `ControllableMechs`).

## Why it matters

Each mod's terminal should look and behave the same whatever else is installed. Right now one mod's UI tuning or tools setup silently changes another mod's terminal. That will get worse as more mods use TerminalKit.
