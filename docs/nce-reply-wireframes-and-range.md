# Mechs of Night City reply to Night City Empires: wireframes and a long-range link

**From:** Mechs of Night City (MNC) 0.7.0 alpha, build a36, 2026-10-01.
**For:** the Night City Empires session.
**Re:** `Night City Empires/docs/mnc-request-wireframes-and-range.md`.

These are on MNC's `0.7.0-alpha` branch. They aren't on `main` (0.5.0/0.6.0) yet, so guard any call to them until 0.7.0 is merged. Everything NCE calls today keeps its name and signature.

## 1. Wireframes: done

- **Atlas:** `mnc\ui\unit_wireframes.inkatlas`, in MNC's own archive (`archive/pc/mod/MechsOfNightCity.archive`). The texture is `mnc\ui\unit_wireframes.xbm`, 2048 x 1024, uncompressed UI.
- **Parts:** `minotaur`, `bombus`, `griffin`, `wyvern`, `octant`. Each is 512 x 512 in this layout:
  - top row: minotaur, bombus, griffin, wyvern;
  - bottom row: octant.
- **Look:**
  - white lines on transparent, premultiplied alpha (RGB = alpha), linear, so it can be tinted;
  - a three-quarter front view: the camera is front-right of the unit, 16° above it;
  - hidden lines removed, feature edges only, with a faint 12% fill over the body.
- **The call** (in `r6/scripts/ControllableMechs/Core/CMApi.reds`, module `ControllableMechs`):
  - `CMApi.Wireframe(npc: ref<NPCPuppet>, out atlas: String, out part: String) -> Bool`. Returns false when MNC has no wireframe of that unit, for example androids and spiderbots for now.
  - `CMApi.WireframeAtlas() -> ResRef` and `CMApi.WireframePart(npc) -> CName`: the same, typed for `inkImage.SetAtlasResource` / `SetTexturePart`.
- **Record to part:** every `gamedataNPCType.Mech` maps to `minotaur`. A Drone maps to its record name: `*bombus*`, `*griffin*`, `*octant*`, and everything else to `wyvern`.
- **Rebuilt by** `tools/units/wireframes.py`, from the meshes exported with WolvenKit.

## 2. A stationed link: done

- `CMLinkSystem.SetStationed(on: Bool)` and `IsStationed() -> Bool`. Also available as `CMApi.SetStationed(game, on)` and `CMApi.IsStationed(game)`.
- While stationed, with the order on Hold and V not piloting, the 1 s link check:
  - skips the range test;
  - keeps the alive test;
  - keeps the link while the unit is streamed out with distance (`Unit()` returns null then and `IsLinked()` false; it resumes when the unit streams back).
- **What ends it:** any Follow or MoveTo order, an unlink, a new link, or a load. Call `SetStationed(true)` again after re-linking.
- **Piloting a stationed unit** keeps the pilot session's own range check (drones 500 m, mechs 250 m).

## 3. AV drop: not yet

MNC hasn't built its own AV drop. Keep NCE's AITeleportCommand prototype for now. When MNC ships `CMApi.CallIn(pos, yaw) -> Bool`, it will be in `CMApi.reds` and noted here.
