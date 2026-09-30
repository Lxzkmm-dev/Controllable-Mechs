# Controllable Mechs

A Cyberpunk 2077 mod, written in redscript, that lets V take control of the game's robotic NPCs (mechs, androids, drones and spiderbots) through a Robot Link terminal built on TerminalKit, and pilot a Militech Minotaur directly: its sensor feed, its legs and both MK.31 HMGs. Quest NPCs are refused so a link can't break a story scene.

**Version 0.2.0.** The pilot mode is the control framework (`ControllableMechs.Control`); it replaced the alpha's Pilot Mode. See CHANGELOG.md.

## Keys

- **]**: open the Robot Link terminal.
- **[**: link the robot you are looking at (within 60 m).
- **\\**: pilot the linked mech, and disconnect again.
- All three can be rebound in Mod Settings. The defaults avoid K, J and L, which are vanilla crafting, the journal and Night City Empires' Fixer Link.
- While piloting (shown as key tags on the HUD):
  - **WASD**: walk, relative to where you look. A and D alone turn the chassis.
  - **Mouse**: aim. The guns and the chassis follow with weight.
  - **LMB**: fire the MK.31s. **RMB**: optics (MMB in the split fire mode, where RMB is the right gun).
  - **G**: missile strike on the reticle.
  - **B**: cycle the fire mode. **V**: switch between the sensor view and the chase view.

## Piloting

- **View:** the game's own free camera entity sits on the mech's sensor mount, or behind it in the chase view, and takes over the view. It turns heavily: a soft spring, capped turn rates, and a limit on how far the view can lead the guns. Footfalls jolt it. Recoil is a separate, capped shake of the picture that never moves the aim (CONFIG > RECOIL). Both views pull in when a wall is between the camera and the mech.
- **Aim:** the mech's own arms aim. Four look-at requests (the rig's LeftWeapon, RightWeapon, Weapon and Chassis parts) follow a marker on the reticle point, and the chassis turns toward it at a capped, accelerating rate. The guns fire while they swing onto the reticle (rounds go to the reticle point); CONFIG > HOLD FIRE UNTIL ON TARGET makes each gun wait until its barrel is within 4 degrees. The HUD shows each gun's state.
- **Guns:** both MK.31s fire through the game's NPC firing call (`AIWeapon.Fire`) at the reticle point, with the mech as owner, which is the one call that deals damage. A hook on the damage pipeline makes V the instigator, so kills, XP and NCPD heat are V's (CONFIG > KILLS CREDITED TO V). Round speed is four times the NPC default while piloting. The barrels spin up, and each gun heats and locks at 100% until it cools to 35%.
  - Fire modes: **staggered** (default), **linked salvo**, **split** (LMB left gun, RMB right gun).
- **The mech's own AI is held off** while piloting: its stimulus reactions (what made it turn and walk toward gunfire), senses and target tracking are off, its state is kept relaxed, and the game's threat functions skip it (being hit or a squad-mate's target gives it no target of its own). All restored on disconnect.
- **Hull:** the mech's health is multiplied while piloted (CONFIG > HULL, 4 by default), and a beep sounds when integrity is low.
- **HUD:** the vanilla HUD fades out and a Militech overlay replaces it: reticle with per-gun markers and range, compass tape and heading, a weapons plate (heat, fire mode, missile), a chassis plate (integrity, signal, speed), and a warning plate. It is built from the game's own HUD art, referenced by path (the Basilisk tank HUD, the Militech turret HUD, the shadow and glitch atlases), laid out on a 2160-high design space and scaled to the screen height. Its motion (idle flicker, damage jolt, hot-gun pulse, warning sweep) is engine animations started on events.
- **V:** V stays where they are, locked in place by the game's gameplay restrictions. A save lock is held while piloting.
- **Disconnects:** you are disconnected when you press \\, the mech is destroyed, the signal drops (250 m), the link closes, or the session ends. Damage to V also disconnects you, like camera hacking; this can be turned off in CONFIG.
- **CONFIG** (lengths in feet and inches; the rangefinder stays in metres): fire mode, kill credit, recoil, hull, turn speed, disconnect-when-hit, mouse sensitivity, the view, the chase camera (distance, height, side offset, shoulder), the sensor mount, the palette, and diagnostics.
- **Diagnostics** (CONFIG > DIAGNOSTICS, off by default): traces hits and session events to the game log, tag `ControllableMechs`.
- **Test spawn:** the terminal's MOTOR POOL section spawns a Militech Minotaur (`Character.q003_militech_mech`) in front of V and links it. It is not saved.

## Layout

- `r6/scripts/ControllableMechs`
  - `Mech/CMLinkSystem.reds`: the link. It holds the one linked robot by EntityID, sends its orders (follow, hold, move to a point), reads its telemetry and spawns the test Minotaur.
  - `Control/CMCSession.reds`: the pilot session. Enter and exit, the per-frame loop, input, the camera, the reticle trace, exit checks and V's restrictions.
  - `Control/CMCUnit.reds`: what a pilotable unit must provide.
  - `Control/CMUMinotaur.reds`: the Minotaur: look-at aim, the fire gate, the chassis turn, walking, AI suppression, hull, audio and the missile.
  - `Control/CMCHits.reds`: the damage pipeline hook (V's credit, the hit marker, the diagnostics trace).
  - `Pilot/CMPilotSystem.reds`: the settings. They are kept in `r6/storages/ControllableMechs/settings.txt`, not in the save, so loading an older save never changes them.
  - `Pilot/CMPilotRig.reds`: the weighted camera math (no game calls).
  - `Pilot/CMPilotGuns.reds`: the two HMGs: discovery, fire modes, cadence and heat.
  - `Pilot/CMPilotHud.reds`: the Militech overlay on the HUD layer.
  - `UI/CMContent.reds`: the Robot Link pages (a TerminalKit `TKContent`): UNIT, CONFIG and TOOLS (TerminalKit Tools).
  - `UI/CMTerminal.reds`: the terminal, a subclass of TerminalKit's `TKPopup` frame, with its own style, font and palette.
  - `Core/CMInput.reds`: the keys.
- `r6/input/ControllableMechs.xml`: the key bindings (Input Loader).
- `r6/tweaks/ControllableMechs/mech.yaml`: the missile's attack record (TweakXL).
## Requirements

- redscript
- **TerminalKit** (the standalone TerminalKIT mod, with TerminalKit Tools). This mod doesn't ship its own copy, so there is only ever one TerminalKit in the load order.
- Codeware
- TweakXL
- RedFunctions (TerminalKit uses it, and the settings file is written through it)
- Input Loader
- Optional: Mod Settings, to rebind the keys.

## How it runs

- While no robot is linked, nothing runs.
- While a robot is linked, one check runs every second: is it still there, alive and in signal range (250 m)? If not, the link drops.
- While piloting:
  - Every frame: the camera and the guns. Nothing else runs per frame.
  - Ten times a second: walk orders, HUD values, AI suppression and the disconnect checks.
  - The raw keyboard and mouse callbacks are registered only while piloting.
- Orders are one AI command at a time. The previous command is cancelled before the next one is sent.
- The terminal builds each page fresh from the link system when it is shown, so it keeps no state and costs nothing while it is closed.
- Robots are looked up by EntityID when needed and never held by a strong reference, so a despawned robot cannot crash the mod.

## Roadmap

1. **Command mode:** link a robot, then order it to follow, hold or move to a target.
2. **Piloting the Minotaur:** the control framework, with the sensor and chase views, HUD, both HMGs and the missile.
3. **More mechs** on the same framework.
4. **Attack orders:** send the robot after the target you look at.
5. **Your own mech:** spawn one, persist it in the save, and call it in.
