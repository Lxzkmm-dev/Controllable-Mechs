# Controllable Mechs

A Cyberpunk 2077 mod, written in redscript, that lets V take control of the game's robotic NPCs (mechs, androids, drones and spiderbots) through a Robot Link terminal built with TerminalKit. Quest and boss NPCs are refused so a link can't break a story scene.

Early scaffold. It compiles against the game, but has not been tested in game yet.

## Layout

- `r6/scripts/ControllableMechs`
  - `Mech/CMLinkSystem.reds`: the link. It holds the one linked robot by EntityID, sends its orders (follow, hold, move to a point) and reads its telemetry.
  - `UI/CMContent.reds`: the Robot Link pages (a TerminalKit `TKContent`).
  - `UI/CMTerminal.reds`: the terminal frame (a Codeware `InGamePopup` with a `TKView`).
  - `Core/CMInput.reds`: the keys, K to open the Robot Link and J to link the robot you are looking at.
- `r6/scripts/TerminalKit`: TerminalKit, copied from `Lxzkmm-dev/Night-City-Empires-assets` (branch `main`, commit b0033b7).
- `r6/input/ControllableMechs.xml`: the key bindings (Input Loader).

## Requirements

- redscript
- Codeware
- RedFunctions (TerminalKit uses it)
- Input Loader
- Optional: Mod Settings, to rebind the keys.

## How it runs

- While no robot is linked, nothing runs.
- While a robot is linked, one check runs every second: is it still there, alive and in signal range (250 m)? If not, the link drops.
- Orders are one AI command at a time. The previous command is cancelled before the next one is sent.
- The terminal builds each page fresh from the link system when it is shown, so it keeps no state and costs nothing while it is closed.
- The robot is looked up by EntityID when needed and never held by a strong reference, so a despawned robot cannot crash the mod.

## Roadmap

1. **Command mode (this scaffold):** link a robot, then order it to follow, hold or move to a target.
2. **Attack orders:** send the robot after the target you look at.
3. **Direct drive:** steer the robot with WASD while the camera rides it. Every 0.1 s, a move command goes to a point ahead in the direction you are steering, and this timer only runs while you are driving. Still to work out: locking V's own movement and attaching the camera.
4. **Your own mech:** spawn one, persist it in the save, and call it in.

## TerminalKit and other mods

redscript stops with duplicate definitions if two different paths define the same `TerminalKit` classes. So every mod has to ship TerminalKit at exactly `r6/scripts/TerminalKit`, where the copies overwrite each other, and the versions have to be compatible. A cleaner long-term option is to publish TerminalKit as its own dependency.
