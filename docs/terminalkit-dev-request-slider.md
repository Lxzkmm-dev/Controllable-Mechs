# TerminalKit dev request: sliders pass ":value" when the row's arg is empty

**From:** Controllable Mechs (2026-09-30)
**Severity:** high for any mod using `TKPage.Slider` with an empty arg; its sliders silently never change anything.

## What happens

`TKView.SlideCommit` (TKView.reds, around line 1138) hands the slider's value to the provider as:

```redscript
act.Act(row.action, row.arg + ":" + IntToString(sl.value));
```

When the row's arg is empty, the provider receives `":230"` instead of `"230"`.

## What the docs promise

- README.md: "Controls hand their value on as `arg + ":" + value` (just the value when the row's arg is empty)."
- TKView already has the helper for that: `private static func Prefix(arg: String) -> String = StrLen(arg) > 0 ? arg + ":" : ""` (around line 404). Dropdowns and the pager honour it; the slider doesn't.

## Effect on a provider

A provider that follows the README writes `StringToInt(arg, current)`. `StringToInt(":230", current)` fails and returns `current`, so every slider appears to snap back to its old value when released. Controllable Mechs' SETTINGS page (camera height, forward, chase distance and height, traverse, sensitivity, damage) has never changed anything because of this.

## Requested fix

In `SlideCommit`:

```redscript
act.Act(row.action, TKView.Prefix(row.arg) + IntToString(sl.value));
```

Please also check any other control that builds `row.arg + ":"` by hand.

## Our workaround (no TerminalKit changes)

Controllable Mechs reads the value after the last ":" (`CMContent.Str` / `CMContent.Val`). It works with both the current and the fixed behaviour, so the fix won't break us.
