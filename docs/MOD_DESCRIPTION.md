# Mechs of Night City

Take control of Night City's war machines. Link to a robot, then climb into the neural uplink and pilot a Militech Minotaur yourself: its legs, its sensors, and both of its MK.31 heavy machine guns.

## What it does

- **Robot Link:** a rugged Militech field terminal (built on TerminalKit). Link any mech, android, drone or spiderbot you look at and order it to follow, hold, or move to a target. Quest-critical robots are left alone.
- **Pilot a Minotaur:** press \ to take over the linked mech.
  - Walk it with WASD and aim with the mouse. The chassis and guns follow with real weight.
  - Fire both MK.31s in staggered, linked-salvo or split mode, with barrel spin-up and heat. Guns fire while they swing onto target.
  - Launch missile strikes (G), and zoom through its optics (RMB).
  - Switch between the sensor view and a third-person chase camera (V).
- **A proper fire-control HUD:** built from the game's own tank and turret HUD art, with a compass tape, per-gun reticles, segmented hull and heat bars, and warnings. It flickers when you boot up and tears when the mech takes a hit.
- **It fights like a mech:**
  - The mech's own AI stays out of the way while you drive.
  - Enemies you engage turn their fire on the mech.
  - The hull is reinforced while piloted, with a low-integrity alarm.
  - Kills can count for V.
- **Configurable:** fire control, recoil, hull strength, turn speed, the chase camera (distance, height, shoulder offset), the sensor mount, the palette, and an option to hide V from enemies while linked. Settings are kept outside your save.

## Performance

Script-only (redscript): no CET/Lua, and no meshes, textures or archives of its own.

- **Not piloting:** no per-frame code, no timers and no raycasts; only a few one-line checks on hits and threats.
- **A robot linked:** one check per second.
- **Piloting:** the camera, aim, HUD and guns run only while you pilot, and everything is removed when you disconnect.

The HUD's animations run in the engine, not in script. The log stays empty unless you turn diagnostics on. This is from a review of the code, not a benchmark.

## Planned

- **Hijack enemy mechs:** a quickhack to seize a hostile mech mid-fight and pilot it against its own side.
- **Your own mech:** a Minotaur that belongs to V, with its damage remembered between deployments.
- **Mech carrier:** drive a heavy truck to the fight, walk to the back and deploy your mech from it.
- **AV drop:** call your mech in by air.
- More mechs and robots on the same pilot framework.

## Requirements

redscript, Codeware, TweakXL, RedFunctions, Input Loader, TerminalKit. Mod Settings is optional, for rebinding keys.

Early build: expect rough edges, and please report what you find.
