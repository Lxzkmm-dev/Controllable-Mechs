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
  - The position is pinned to the sensor mount, so it no longer drifts off the mech or shakes against its steps.
  - The weight is in the torso turn, footfall jolts and recoil.
  - The default mount is lower and further forward: 2.3 m up, 2.6 m ahead.
  - Height, forward offset and mouse sensitivity can be tuned live in SETTINGS.
- **Terminal:** built on the standalone TerminalKit. It has LINK, SETTINGS and TOOLS (TerminalKit Tools) tabs, and the palette is saved.
- **Test tools:** spawn a Militech Minotaur from the terminal.
- **Diagnostics:** an optional DBG readout on the pilot HUD (SETTINGS > DEBUG READOUT). Log lines, including a note when the mech jumps more than 3 m in one frame, go to TOOLS > LOG.

Known issues:
- **Mech jumps:** the mech has been seen jumping away while piloted. That's now logged so the cause can be found.
- **Jump key:** Space can still make V jump if the game's NoJump restriction doesn't hold.
- **Guns:** firing is not yet confirmed in game.
- **Gamepad:** not supported yet.
