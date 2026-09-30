# Controllable Mechs

A Cyberpunk 2077 mod, written in redscript, that lets V take control of the game's robotic NPCs (mechs, androids, drones and spiderbots) through a Robot Link terminal built on TerminalKit, and pilot a Militech Minotaur directly: its sensor feed, its legs and both MK.31 HMGs. Quest NPCs are refused so a link can't break a story scene.

**Version 0.1.0 Alpha.** Linking and Pilot Mode work in game; see CHANGELOG.md for what's in it and the known issues.

## Keys

- **K**: open the Robot Link terminal.
- **J**: link the robot you are looking at (within 60 m).
- **L**: pilot the linked mech, and disconnect again. L always disconnects while piloting, even if it has been rebound.
- While piloting:
  - **WASD**: walk, relative to where the torso looks. **Shift**: run.
  - **Mouse**: turn the torso.
  - **LMB**: fire.
  - **RMB**: optics (x2).
  - **B**: cycle the fire mode.

## Pilot Mode

- **View:** the game's own free camera entity (`base\entities\cameras\simple_free_camera.ent`) sits on the mech's sensor mount and takes over the view.
- **Weight:** the camera rides a ring around the mech's centre, placed by where you look (not by the chassis, which turns in heavier AI steps and catches up). The weight is in how it turns and shakes:
  - the torso turn speeds up, is capped at a traverse rate, overshoots a little and settles;
  - every footfall jolts and rolls the view;
  - each shot kicks it.
  - Height, forward offset and mouse sensitivity are sliders in SETTINGS and apply live.
- **Guns:** both MK.31s fire through the game's NPC firing call (`AIWeapon.Fire`) at the point under the reticle, so rounds leave the real muzzles.
  - Fire modes (terminal Settings, or B):
    - **staggered** (default): LMB fires both, barrels alternating;
    - **linked salvo**: LMB fires both at once;
    - **split**: LMB left gun, RMB right gun, MMB optics.
  - Each gun heats as it fires and locks at 100% until it cools to 35%.
- **HUD:** the vanilla HUD fades out and a Militech overlay replaces it:
  - reticle with barrel markers and range;
  - heading;
  - integrity and signal bars, speed;
  - the fire mode;
  - per-gun heat and state;
  - key hints.
- **V:** V stays where they are, locked in place by the game's gameplay restrictions. A save lock is held while piloting.
- **Disconnects:** you are disconnected when you press L, the mech is destroyed, the signal drops (250 m), the link closes, or the session ends. Damage to V also disconnects you, like camera hacking; this can be turned off in Settings.
- **Test spawn:** the terminal's TEST section spawns a Militech Minotaur (`Character.q003_militech_mech`) 14 m in front of V and links it. It is not saved.

## Layout

- `r6/scripts/ControllableMechs`
  - `Mech/CMLinkSystem.reds`: the link. It holds the one linked robot by EntityID, sends its orders (follow, hold, move to a point), reads its telemetry and spawns the test Minotaur.
  - `Pilot/CMPilotSystem.reds`: Pilot Mode. It handles enter and exit, the per-frame loop, raw input, walk orders, exit checks and V's restrictions.
  - `Pilot/CMPilotRig.reds`: the weighted camera math (no game calls).
  - `Pilot/CMPilotGuns.reds`: the two HMGs: discovery, fire modes, cadence and heat.
  - `Pilot/CMPilotHud.reds`: the Militech overlay on the HUD layer.
  - `UI/CMContent.reds`: the Robot Link pages (a TerminalKit `TKContent`): LINK, SETTINGS (fire mode, disconnect-when-hit, palette), and TOOLS (TerminalKit Tools: inspect, spawn, TweakDB).
  - `UI/CMTerminal.reds`: the terminal, a subclass of TerminalKit's ready-made `TKPopup` frame.
  - `Core/CMInput.reds`: the keys.
- `r6/input/ControllableMechs.xml`: the key bindings (Input Loader).

## Requirements

- redscript
- **TerminalKit** (the standalone TerminalKIT mod, with TerminalKit Tools). This mod doesn't ship its own copy, so there is only ever one TerminalKit in the load order.
- Codeware
- RedFunctions (TerminalKit uses it)
- Input Loader
- Optional: Mod Settings, to rebind the keys.

## How it runs

- While no robot is linked, nothing runs.
- While a robot is linked, one check runs every second: is it still there, alive and in signal range (250 m)? If not, the link drops.
- While piloting:
  - Every frame: the camera and the guns. Nothing else runs per frame.
  - Ten times a second: walk orders, HUD values and the disconnect checks.
  - The raw keyboard and mouse callbacks are registered only while piloting.
- Orders are one AI command at a time. The previous command is cancelled before the next one is sent.
- The terminal builds each page fresh from the link system when it is shown, so it keeps no state and costs nothing while it is closed.
- Robots are looked up by EntityID when needed and never held by a strong reference, so a despawned robot cannot crash the mod.

## Roadmap

1. **Command mode:** link a robot, then order it to follow, hold or move to a target.
2. **Pilot Mode (first build, Minotaur):** direct control with the weighted camera, HUD and both HMGs.
3. **Attack orders:** send the robot after the target you look at.
4. **Your own mech:** spawn one, persist it in the save, and call it in.
