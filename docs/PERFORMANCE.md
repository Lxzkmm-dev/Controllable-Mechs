# Controllable Mechs: performance

This is an analysis of what the mod's code does and when, read from the source (version 0.2.0, 2026-09-30). It is not a benchmark: no frame times or FPS were measured. The numbers below are counts of work, not milliseconds.

## Short version (for a mod page)

> **Performance.** Controllable Mechs is script-only (redscript): no CET/Lua, no meshes, textures or archives of its own. While you are not piloting, it runs no per-frame code, no timers and no raycasts; it adds only a handful of one-line checks to a few game functions. With a robot linked it does one check per second. All the real work (camera, aim, HUD, guns) runs only while you pilot, and stops completely when you disconnect. The pilot HUD is built when you link in and removed when you leave, using the game's own HUD textures. Settings are kept in a small file instead of your save, and the log stays empty unless you turn diagnostics on.

## What runs when

### Always, from game start (nothing linked)

No timers, no per-frame code, no raycasts, no file writes. What exists:

| Hook | When it runs | Cost each time |
|---|---|---|
| Three key listeners (open terminal, link, pilot) | When one of those keys is pressed | A debounce check |
| Wrap on `PlayerPuppet.OnAction` | Every game input action | One null check |
| Wrap on `DamageSystem.ProcessPipeline` | Every hit in the world | Read the hit's weapon, one flag check |
| Wrap on `TargetTrackingExtension.OnHit` | Every hit on an NPC | Two flag checks and a weapon read; for a weaponless hit by V, one system lookup |
| Wraps on `TargetTrackingExtension.InjectThreat` (3) and `OnEnemyPushedToSquad` | When the game shares a threat with an NPC | One flag check |
| Settings file | First time a setting is read after loading | One small text file read (under 1 KB) |

The raw keyboard and mouse callbacks are registered when a pilot session starts and removed when it ends, so outside a session no key press or mouse move reaches the mod.

### A robot is linked, not piloted

One check per second: is the robot still there, alive and in range. Orders (follow, move) are single AI commands, sent when you give them.

### The terminal is open

Pages are built when shown and hold no state. Nothing runs while it is closed.

### Piloting

Every frame:

- Camera: spring math (no game calls), one static raycast to keep the camera out of walls, one transform set on the camera entity.
- Reticle: two raycasts (world geometry, then characters and vehicles).
- Aim: one transform set on the look-at marker; two barrel-to-reticle angle calculations.
- Chassis: at most one rotation call, and only while the body is turning or has been moved off its heading.
- Guns: cadence and heat arithmetic; per round fired, one fire call and up to three effects. A gun that fires before its barrel has reached the reticle adds two raycasts for that round.
- HUD: the compass tape, gun reticles and heat cells are touched only when their value changes by a visible amount.

Ten times a second:

- Disconnect checks (robot alive, in range, V not hit).
- AI suppression checks (three cheap reads, action only when something changed).
- Hull read, walk orders (one raycast, and an AI move command only when the direction changes).
- HUD text refresh.

On events only: HUD animations (idle flicker, damage jolt, warning pulse, overheat pulse) are engine animations started when the event happens; no script runs for them per frame.

On leaving: the camera, marker entity, HUD, status effects, stat modifiers, input callbacks and the save lock are all removed.

## Footprint

- 14 script files, about 5,500 lines; one TweakXL record (the missile's attack); one Input Loader file. About 230 KB in total.
- No archives. The HUD references four of the game's own atlases by path.
- The pilot HUD is roughly 280 ink widgets (60 of them faint scanlines, 60 bar cells), built once per link-in.
- Two entities exist only while piloting: the camera and an invisible aim marker.
- Settings live in `r6/storages/ControllableMechs/settings.txt`, written only when a setting changes. The save holds only a few leftover numbers from earlier builds, kept so old saves still load.
- The log file is written only when CONFIG > DIAGNOSTICS is on, and hit traces are limited to 25 lines per 5 seconds.

## What this analysis does not cover

- No frame-time or FPS measurement has been taken, with or without the mod. Three raycasts and a few transform sets per frame are small next to the game's own per-frame work, but that is an expectation, not a measurement.
- The cost of the game's own systems the mod drives (the Minotaur's AI walking, its animation, the rounds and effects it fires) is the game's, and is the same as when an AI Minotaur does those things.
- Behaviour with several hundred NPCs being hit at once has not been profiled; the hit hooks are a few field reads each.
