# Drone HUD mockups

Python scripts that draw the approved drone HUD mockups over an in-game screenshot.
Nothing here is loaded by the game.

| Script | Draws | Background it needs (in `shots/`) | Output (in `out/`) |
|---|---|---|---|
| `octant.py` | Octant gunship HUD | `oct_base.png` (2000x936, cleaned screenshot) | `octant_gunship_hud_mockup.png` |
| `griffin.py` | Griffin assault HUD | `grf_base.png` (made by `base.py`) | `griffin_assault_hud_mockup.png` |
| `wyvern.py` | Wyvern recon HUD | `wyv_base.png` (made by `base.py`) | `wyvern_recon_hud_mockup.png` |
| `bombus_mock.py` | Bombus FPV HUD v2 | `bombus_raw.png` (raw a37 screenshot; the script inpaints the old HUD itself) | `bombus_hud_mockup_v2.png` |
| `base.py` | Inpaints the old HUD out of `wyv_raw.png` and `grf_raw.png` | raw Wyvern/Griffin screenshots | `shots/wyv_base.png`, `shots/grf_base.png` |
| `kit.py` | Shared drawing kit (text, lines, corner brackets, arcs, bars, notes, sprite paste), fonts and paths | | |

`*_sprite.png` are the wireframe scans of the in-game drone models used for the damage
schematic (HUD rule: schematic sprites are only ever wireframe scans of a game asset).

## Running

Python 3.9+ with Pillow 10.1 or newer. `base.py` also needs OpenCV and NumPy.

```
pip install pillow opencv-python-headless numpy
python tools/hud/mockup/octant.py
```

Scripts can run from any folder. Put screenshots in `tools/hud/mockup/shots/`; results go to
`tools/hud/mockup/out/` (both are git-ignored). The screenshots are not in the repo: if one is
missing the script prints a warning and draws on a flat grey placeholder so the layout still
renders. The inpaint boxes in `base.py` and `bombus_mock.py` match the original screenshots,
so a new screenshot needs new boxes (or a clean shot with no HUD, renamed to the `*_base.png` name).

Fonts: Liberation Sans / DejaVu Sans Mono on Linux, Arial Bold / Consolas Bold on Windows.

## Relation to the in-game HUD

These are pictures for Omar to approve, not game assets. The in-game shape atlas is built by
`tools/hud/uikit.py`; the two share no code. `Kit.bar` here draws segmented cells, but in-game
bars, arcs and rings must be smooth continuous shapes, and every HUD has to anchor to the real
screen edges on an ultrawide monitor.
