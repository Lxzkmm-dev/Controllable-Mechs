# Changelog

## 0.1.0 Alpha

The first playable build: the proof of concept works in game.

- **Robot Link:** link any mech, android, drone or spiderbot you look at (J, or from the terminal). Quest NPCs are refused. Orders: follow, hold, move to target.
- **Pilot Mode (Militech Minotaur):** take the mech's sensor feed with L.
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
- **Aim along the barrels (new default):** each round now flies along its own MK.31 barrel, so the rounds always leave the way the muzzle flash does. Two diamond pips on the HUD show where the barrels point. SETTINGS > AIM MODE can switch back to aiming at the reticle, where the guns wait for the chassis to line up.
- **Traverse:** the torso turns slower and heavier by default, 40 deg/s with a softer start. There's a TRAVERSE SPEED slider in SETTINGS.
- **Sound:**
  - the game's own sensor-camera servo loops while the view traverses;
  - a heavy servo thunk marks each start;
  - the chassis plays the Minotaur's own turn-in-place sound when it swings round.
- **No run:** Shift no longer does anything, because the Minotaur's "run" came out slower than its walk.
- **Walls:** walk orders stop 2.5 m short of walls and buildings instead of targeting through them. An unreachable target seems to be what made the game teleport the mech.
- **Third-person chase camera:** V while piloting, or SETTINGS > VIEW. The camera sits behind and above the mech, 8.5 m back and 4.2 m up by default, with sliders for both. Aiming starts past the mech so it can't hit itself.
- **No camera clipping:** in both views, when geometry is between the mech and the camera, the camera snaps in to just short of it, then eases back out once the way is clear.
- **Diagnostics:** each trigger pull logs how far each barrel and the chassis are off the view (TOOLS > LOG).

Known issues:
- **Mech jumps:** the mech has been seen jumping away while piloted. That's now logged so the cause can be found.
- **Jump key:** Space can still make V jump if the game's NoJump restriction doesn't hold.
- **Guns:** they fire in game. Whether the flash and the rounds now line up is still to be confirmed.
- **Gamepad:** not supported yet.
- **Backing up (S):** on builds before 4e54241 the camera followed the chassis's facing, so when the Minotaur turned round to back up, the view ended up behind and in front of it. The camera now follows the view's facing; still to confirm in game.

