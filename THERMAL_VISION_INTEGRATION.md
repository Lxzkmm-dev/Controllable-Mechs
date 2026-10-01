# Thermal vision for drones and mechs: analysis of Kiroshi Optics Thermal Vision 1.5 and integration plan

Source: "Kiroshi Optics Thermal Vision" 1.5 (Nexus 32729), uploaded by Omar 2026-10-01. Omar has the
author's permission to use it with credit on the Nexus page. Goal (Omar): a thermal toggle for every
drone and mech, folded into Mechs of Night City as our own code, no extra requirement, debloated,
optimised, localization stripped, and sharper and more accurate for drone use.

## 1. What the mod is

| Part | Size | What it does |
|---|---|---|
| `archive/pc/mod/Kiroshi Optics Thermal Vision.archive` | 676 KB | 11 files: 3 `.effect` files (`base\fx\qc\thermal_vision_orange / _spike / _white_hot.effect`) and 8 colour-grading LUT textures (`base\weather\24h_basic\luts\qc\...`: `military_inverted_01`, `inverted_bw_01`, `qc_world` SDR/HDR variants). Kraken-compressed; needs WolvenKit to open. |
| `r6/scripts/ThermalVision/ThermalVisionSystem.reds` | 28 KB | The toggle: registers the 3 effects on V's `fx_status_effects` spawner, starts/stops one with `GameObjectEffectHelper.Start/StopEffectEvent`. Everything else is gating. |
| `Settings.reds` | 6.5 KB | Mod Settings keybinds (F10 toggle, Shift+F10 cycle) + night-vision provider choice; a persistent `ScriptableService` for the last mode. |
| `Equipment.reds` | 0.7 KB | Equipment listener: thermal needs Kiroshi optics quality >= 4. |
| `TrueNightVisionIntegration.reds` | 1.7 KB | Conditional bridge to the True Night Vision mod. |
| `Localization/*.reds` | 19 files | Strings for the settings UI and the optics description (only English has content). |
| `r6/tweaks/ThermalVision.yaml` | 2.9 KB | TweakXL: appends a description package to ~60 Kiroshi optics records. |
| CET `KiroshiThermalVisionBridge/init.lua` | 3.9 KB | Runs EVERY FRAME (`onUpdate`) to sync quest facts with the CET Night Vision mod. |

**The actual thermal look is a screen-space colour grade.** Each `.effect` swaps the scene's colour
LUT for a remap (orange "thermal", red "spike", white-hot greyscale). It does not know what is hot:
it maps brightness to colour, so a bright wall reads as "hot" and a person in shadow reads as cold.

## 2. Bloat and performance findings

- **Always-on 4 Hz loop.** `StartVisionMonitor` re-arms a 0.25 s DelayCallback for the whole session,
  even when thermal has never been switched on (checks status effects and True Night Vision).
- **Every-frame CET script.** The Lua bridge does quest-fact reads/writes on every frame while in game.
- **Five blackboard listeners + an equipment listener + a quest-fact listener** for the whole session,
  to suspend in menus, braindance, device takeover, photo mode and death.
- **Always-registered key callback** for F10/Shift+F10 (and controller keys) all session.
- **Quest facts as a message bus** between redscript and Lua (5 facts written repeatedly).
- **TweakXL edits to ~60 item records** only to add a tooltip line.
- **19 localization files** for ~20 strings; 18 of them are 75-byte stubs.

None of this is needed inside MNC: our piloting session already owns the input, the camera and
the lifetime, and it already stops everything on unlink, menus and death.

## 3. What MNC keeps

- The **archive's 3 effects and 8 LUTs** (renamed under `mnc\fx\thermal\`, packed into
  MechsOfNightCity.archive, so no second archive and no conflict with the original mod if a user has
  both installed).
- The **mechanism**: an `entEffectDesc` added to an effect spawner, started and stopped by name.
- Credit: "Thermal vision effects adapted from Kiroshi Optics Thermal Vision by <author>, used with
  permission" on the MNC Nexus page and in the README/CHANGELOG.

Everything else is dropped: Mod Settings keybinds, mode storage service, optics requirement,
equipment and blackboard listeners, monitor loop, True Night Vision and CET bridges, TweakXL file,
all localization (MNC's HUD and terminal text are plain English already).

## 4. MNC design (`CMThermal`, about 80 lines)

- Exists only while piloting: created by the session on link-in, torn down on unlink. Zero cost
  otherwise: no listeners, no timers, no key callbacks outside a session.
- Key: one pilot key toggles, Shift+key cycles mode (default key to be chosen against
  [[controllable-mechs-keybinds]]; the session already consumes pilot keys, so no vanilla clash).
- Modes, military order: **WHT** (white-hot, default), **BHT** (black-hot, new: the white-hot LUT
  inverted), **IRN** (the original orange, kept for style). The original "spike" red is dropped.
- HUD: the sensor-mode readout ("SENSOR WHT" on the Octant mockup) shows the live mode; green
  symbology stays readable on grey.
- Per unit: available on every drone and mech; CONFIG > OPTICS lists THERMAL (default mode).

## 5. Sharper and more accurate for drone use

1. **Sharper image (archive edit, WolvenKit):** rebuild the LUTs for a clean military FLIR look:
   steeper contrast curve, no orange tint in WHT/BHT, slight edge sharpening if the effect exposes
   it, and remove any vignette, grain or chromatic aberration the effects add (check each `.effect`'s
   post-process params in WolvenKit before deciding).
2. **Real heat, not brightness (script):** while thermal is on, give hot things a white heat glow on
   top of the grade, so a person in shadow still reads hot:
   - living NPCs and animals: full-body fill highlight (the game's forced vision appearance /
     highlight system that scanners use; exact API to confirm in the Codeware dump);
   - running vehicles: engine block / exhaust highlight; drones and mechs: hot;
   - dead bodies fade from hot to cold over ~60 s (nice FLIR detail, cheap: one timestamp each).
   - Performance: only within the sensor range (default 150 m), refreshed 4x a second from one
     spatial query, max ~40 entities, only while thermal is on and piloting.
3. **Zoom pairs with optics:** thermal stays on through RMB optics zoom (the drone sensor view).

## 6. Risks to check first (one spike build)

- The original spawns the effect on **V's** `fx_status_effects`. While piloting, the active camera is
  our free camera. Screen-space grading effects normally render regardless of the camera, but this is
  unverified: spike = start the effect on V while piloting and look. Fallback: add an effect spawner
  to the camera entity or start it on the drone.
- LUT effects may fight the game's weather/time-of-day grading at night or in rain; check day/night.
- The highlight API may outline instead of fill; if fill isn't available, use the strongest outline
  plus the LUT.
