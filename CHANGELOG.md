# Changelog

## 0.2.0

The control framework (`ControllableMechs.Control`) is now the mod's pilot mode. The alpha's Pilot Mode is removed.

- **Aim:** the Minotaur's own arms follow the reticle (look-at requests on its weapon parts), and a gun fires only when its barrel is within 4 degrees of it.
- **Damage and credit:** rounds are fired by the mech at the reticle point, and a damage pipeline hook credits the hits to V.
- **Feel:** a heavy camera, a weighted chassis turn, barrel spin-up, optics (RMB), rounds four times as fast, footfall weight, gun and servo audio, and a missile strike (G).
- **The mech's AI is held off** while piloting, and the hull is multiplied (4 by default) with a low-integrity beep.
- **HUD:** a Militech overlay with the keys built in as tags.
- **Terminal:** UNIT, CONFIG and TOOLS tabs with a military style, font and palette. CONFIG holds every setting, in feet and inches, including a CHASE CAMERA section (distance, height, side offset, shoulder).
- **Removed:** the alpha's Pilot Mode and its settings (aim mode, traverse speed, arm tracking, MK.31 damage, debug readout), the SPIKES tab and all spike code. The hit trace stays behind CONFIG > DIAGNOSTICS, off by default; with it off the mod writes nothing to the game log.
- **Needs** TweakXL for the missile's attack record.
## 0.1.0 Alpha

The first playable build: the proof of concept works in game.

- **Robot Link:** link any mech, android, drone or spiderbot you look at (J, or from the terminal). Quest NPCs are refused. Orders: follow, hold, move to target.
- **Pilot Mode (Militech Minotaur):** take the mech's sensor feed with \\ (was L).
  - WASD walks the mech, relative to where the torso looks.
  - The mouse turns the torso with weight.
  - LMB/RMB fire the two MK.31 HMGs. Fire modes: staggered (default), linked salvo, split.
  - Militech HUD.
  - V is locked in place while piloting, and a save lock is held.
- **Camera:**
  - The position rides a ring around the mech's centre, placed by the view's facing and not the chassis's. The chassis turns in jerky AI steps, and tying the camera to it made the view lurch and hitch during 360s.
  - The weight is in the torso turn, footfall jolts and recoil.
  - The default mount is lower and further forward: 2.3 m up, 2.6 m ahead.
  - Height, forward offset and mouse sensitivity can be tuned live in SETTINGS.
- **Terminal:** built on the standalone TerminalKit. It has LINK, SETTINGS and TOOLS (TerminalKit Tools) tabs, and the palette is saved.
- **Guns and chassis:** the MK.31s are fixed to the body, so the body now keeps turning toward where the torso aims. It follows lazily: turn orders go out when it's 20 degrees off (6 with a trigger held), no more than every 0.8 s. It faces the aim point while walking. The guns only fire once the chassis is within 15 degrees of the reticle, so the muzzle flash and the rounds agree. Until then the HUD shows ALIGNING CHASSIS.
- **Test tools:** spawn a Militech Minotaur from the terminal.
- **Diagnostics:** an optional DBG readout on the pilot HUD (SETTINGS > DEBUG READOUT). Log lines, including a note when the mech jumps more than 3 m in one frame, go to TOOLS > LOG.

### Since the first alpha build
- **Gimballed aim (new default):** rounds go to what the reticle is on, including characters and vehicles (the reticle raycast now checks dynamic objects as well as world geometry), within each gun's travel around its mount: 12 degrees side to side, 40 down and 25 up. You can shoot down at targets again. Beyond that travel, a round stops at the edge of the cone. The HUD pips show where each gun's rounds will land.
- **Aim along the barrels (now an option):** each round now flies along its own MK.31 barrel, so the rounds always leave the way the muzzle flash does. Two diamond pips on the HUD show where the barrels point. SETTINGS > AIM MODE: GIMBALLED, TO THE RETICLE (the guns wait for the chassis to line up) or ALONG THE BARRELS.
- **Traverse:** the torso turns slower and heavier by default, 40 deg/s with a softer start. There's a TRAVERSE SPEED slider in SETTINGS.
- **Sound:**
  - the game's own sensor-camera servo loops while the view traverses;
  - a heavy servo thunk marks each start;
  - the chassis plays the Minotaur's own turn-in-place sound when it swings round.
- **No run:** Shift no longer does anything, because the Minotaur's "run" came out slower than its walk.
- **Walls:** walk orders stop 2.5 m short of walls and buildings instead of targeting through them. An unreachable target seems to be what made the game teleport the mech.
- **Third-person chase camera:** V while piloting, or SETTINGS > VIEW. The camera sits behind and above the mech, 8.5 m back and 4.2 m up by default, with sliders for both. Aiming starts past the mech so it can't hit itself.
- **New default keys:** ] opens the Robot Link, [ links the robot you look at, \\ pilots and disconnects. The old K, J and L clashed: K is vanilla crafting, J the journal, and L opens Night City Empires' Fixer Link, which is why pressing it brought up the Fixer Link. All three can be rebound in Mod Settings.
- **Robot Link in combat:** the keys now live in the Exploration, Combat and Locomotion input contexts, not just Items, which isn't active while fighting. A 0.25 s debounce stops one press from firing twice. The terminal's own combat block is gone too; only menus, pause and photo mode block it.
- **Arm tracking (experimental, on by default):** the mech gets the game's look-at requests for its hands and chest, aimed at an invisible marker on the aim point. The goal is for the arms, and the MK.31 barrel effects, to follow the reticle instead of pointing straight ahead. SETTINGS > ARM TRACKING. Which parts the Minotaur's rig answers to is unknown.
- **MK.31 damage:** a slider in SETTINGS, 100-300% with 150% by default, offsets the aim mismatch. It's a multiplier on the guns' BaseDamage stat while piloting. Whether NPC weapons use that stat is unverified; TOOLS > LOG shows the before and after values.
- **Chase view:** it's closer by default, 6 m back and 3.2 m up. Turning is critically damped (no snap), and the camera's orbit trails the aim so it swings round the mech smoothly.
- **Aim fix:** the reticle ray no longer misses the ground when looking steeply down in the chase view.
- **No camera clipping:** in both views, when geometry is between the mech and the camera, the camera snaps in to just short of it, then eases back out once the way is clear.
- **Diagnostics:** each trigger pull logs how far each barrel and the chassis are off the view (TOOLS > LOG).

Known issues:
- **Mech jumps:** the mech has been seen jumping away while piloted. That's now logged so the cause can be found.
- **Jump key:** Space can still make V jump if the game's NoJump restriction doesn't hold.
- **Guns:** they fire in game. Whether the flash and the rounds now line up is still to be confirmed.
- **Gamepad:** not supported yet.
- **Backing up (S):** on builds before 4e54241 the camera followed the chassis's facing, so when the Minotaur turned round to back up, the view ended up behind and in front of it. The camera now follows the view's facing; still to confirm in game.

