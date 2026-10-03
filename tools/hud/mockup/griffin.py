import math
from PIL import Image, ImageDraw
from kit import Kit, scanlines, font, shot, out

im = shot("grf_base.png", (2000, 809))
GR = (110, 255, 130)
GD = (60, 150, 80)
WH = (236, 246, 236)
RD = (255, 64, 56)
YL = (240, 230, 90)
PANEL = (4, 26, 10, 150)
k = Kit(im, GR)
d = k.d
W, H = im.size
X0, X1 = 285, 1715
CX, CY = 1000, 420


def panel(pts):
    d.polygon(pts, fill=PANEL)
    k.line(pts + [pts[0]], GR, 2)


def hazard(x0, y0, x1, y1, step=10):
    # diagonal stripes clipped to the box
    strip = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    for i in range(-(y1 - y0), x1 - x0, step * 2):
        sd.polygon([(i, y1 - y0), (i + step, y1 - y0), (i + step + (y1 - y0), 0), (i + (y1 - y0), 0)], fill=GR + (230,))
    im.paste(strip, (x0, y0), strip)


# ---- top left: identity block, chevron cut ----------------------------------
panel([(X0, 28), (640, 28), (664, 52), (664, 104), (X0, 104)])
hazard(X0 + 8, 36, X0 + 58, 48)
k.t(X0 + 66, 32, "MILITECH  GRIFFIN AS-2", 17)
k.t(X0 + 10, 58, "STRIKE", 22, GR)
k.t(X0 + 110, 62, "LINK", 11, GD, mono=True); k.bar(X0 + 150, 63, 90, 9, 0.97, GR)
k.t(X0 + 248, 62, "97%  0.05KM", 11, WH, mono=True)
k.t(X0 + 110, 80, "ROE  WEAPONS FREE", 11, YL, mono=True)

# ---- top centre: heading box -----------------------------------------------
hdg = 352
panel([(CX - 52, 30), (CX + 52, 30), (CX + 64, 48), (CX + 52, 66), (CX - 52, 66), (CX - 64, 48)])
k.t(CX, 34, f"{hdg:03d}", 26, WH, "ma")
for i in range(-9, 10):
    deg = hdg + i * 5
    x = CX + i * 22
    if abs(i) < 3:
        continue
    hgt = 10 if deg % 10 == 0 else 5
    k.line([(x, 48 - hgt / 2), (x, 48 + hgt / 2)], GR, 2)
k.t(CX - 180, 42, "W", 13, GR, "ma"); k.t(CX + 180, 42, "E", 13, GR, "ma")
k.t(CX + 2, 70, "N", 12, GR, "ma")

# ---- top right: combat tally ------------------------------------------------
panel([(1360, 28), (X1, 28), (X1, 104), (1336, 104), (1336, 52)])
hazard(X1 - 58, 36, X1 - 8, 48)
k.t(1350, 34, "HITS", 11, GD, mono=True); k.t(1350, 48, "12", 22, WH)
k.t(1420, 34, "KILLS", 11, GD, mono=True); k.t(1420, 48, "2", 22, GR)
k.t(1490, 34, "THREATS", 11, GD, mono=True); k.t(1490, 48, "2", 22, RD)
k.t(1350, 80, "SPOOL 51%   T+00:09", 11, WH, mono=True)

# ---- centre: gun reticle with heat / rocket arcs, roll wings --------------
R = 74
roll = math.radians(-6)
# left arc = left gun pod heat, right arc = right gun pod heat (fill bottom-up)
k.arc(CX, CY, R, 120, 240, GD, 3)
k.arc(CX, CY, R, 192, 240, GR, 5)             # L 40%
k.arc(CX, CY, R, -60, 60, GD, 3)
k.arc(CX, CY, R, 12, 60, YL, 5)               # R 40%, pod damaged
k.t(CX - R - 12, CY + 34, "L HEAT", 10, GD, "ra", mono=True)
k.t(CX - R - 12, CY + 46, "40%", 12, GR, "ra")
k.t(CX + R + 12, CY + 34, "R HEAT", 10, GD, mono=True)
k.t(CX + R + 12, CY + 46, "40%", 12, YL)
# pipper
d.ellipse((CX - 14, CY - 14, CX + 14, CY + 14), outline=(0, 0, 0), width=4)
d.ellipse((CX - 14, CY - 14, CX + 14, CY + 14), outline=GR, width=2)
d.ellipse((CX - 2, CY - 2, CX + 2, CY + 2), fill=GR)
# roll wings: the only attitude cue, tilting with the bank
for sgn in (-1, 1):
    ax, ay = math.cos(roll) * sgn, math.sin(roll) * sgn
    p0 = (CX + ax * (R + 14), CY + ay * (R + 14))
    p1 = (CX + ax * (R + 70), CY + ay * (R + 70))
    p2 = (p1[0] - math.sin(roll) * 0 + (0), p1[1] + 10)
    k.line([p0, p1, (p1[0], p1[1] + 10)], GR, 3)
k.t(CX, CY - R - 24, "+2°", 12, GR, "ma")
k.t(CX, CY + R + 8, "RNG 41 M", 13, WH, "ma", mono=True)
# incoming-fire chevrons on the ring
for ang in (-35, 205):
    a = math.radians(ang)
    px, py = CX + math.cos(a) * (R + 26), CY + math.sin(a) * (R + 26)
    nx, ny = math.cos(a), math.sin(a)
    tx, ty = -ny, nx
    pts = [(px + nx * 10, py + ny * 10), (px + tx * 10, py + ty * 10), (px - nx * 2, py - ny * 2), (px - tx * 10, py - ty * 10)]
    d.polygon(pts, fill=RD, outline=(0, 0, 0))
k.t(CX + 92, CY - 86, "INCOMING", 11, RD, mono=True)

# ---- target lock + lead ------------------------------------------------------
tx, ty = 1122, 515
s = 26
dia = [(tx, ty - s), (tx + s, ty), (tx, ty + s), (tx - s, ty)]
d.polygon(dia, outline=(0, 0, 0), width=5)
d.polygon(dia, outline=RD, width=2)
k.arc(tx, ty, s + 10, -90, -90 + 252, RD, 3)   # lock 70%
k.line([(tx + s + 12, ty - 10), (tx + 70, ty - 40), (tx + 190, ty - 40)], RD, 1)
k.t(tx + 74, ty - 60, "HOSTILE  41 M", 12, RD, mono=True)
k.t(tx + 74, ty - 36, "LOCK 70%", 12, WH, mono=True)
for i in range(4):
    d.rectangle((tx + 160 + i * 10, ty - 32, tx + 167 + i * 10, ty - 22), fill=RD if i < 3 else (80, 30, 30))
# lead marker
lx, ly = tx - 38, ty - 22
d.ellipse((lx - 6, ly - 6, lx + 6, ly + 6), outline=GR, width=2)
for t0 in range(0, 10, 3):
    f0, f1 = t0 / 10, (t0 + 1.5) / 10
    k.line([(lx + (tx - lx) * f0, ly + (ty - ly) * f0), (lx + (tx - lx) * f1, ly + (ty - ly) * f1)], GR, 1)

# ---- speed and height tapes (angled pointers) ----------------------------
def tape(x, val, label, unit, right):
    top, bot = CY - 110, CY + 110
    k.line([(x, top), (x, bot)], GD, 2)
    for i in range(-5, 6):
        y = CY + i * 20
        ln = 12 if i % 2 == 0 else 6
        k.line([(x, y), (x + (-ln if right else ln), y)], GR, 2)
    bx = x + (-12 if right else 12)
    w = 92
    if right:
        pts = [(bx, CY), (bx - 14, CY - 18), (bx - 14 - w, CY - 18), (bx - 14 - w, CY + 18), (bx - 14, CY + 18)]
        tx_ = bx - 20
        an = "ra"
    else:
        pts = [(bx, CY), (bx + 14, CY - 18), (bx + 14 + w, CY - 18), (bx + 14 + w, CY + 18), (bx + 14, CY + 18)]
        tx_ = bx + 14 + w - 6
        an = "ra"
    d.polygon(pts, fill=(4, 26, 10, 200))
    k.line(pts + [pts[0]], GR, 2)
    k.t(tx_, CY - 13, val, 22, WH, an)
    k.t(x, top - 20, label, 11, GD, "ma", mono=True)
    k.t(x, bot + 6, unit, 11, GD, "ma", mono=True)


tape(CX - 330, "5", "SPD", "KM/H", False)
tape(CX + 330, "8.2", "ALT", "M", True)
k.t(CX + 330, CY + 136, "VS +0.0", 12, WH, "ma", mono=True)

# ---- bottom left: attack run -------------------------------------------------
panel([(X0, 690), (590, 690), (614, 714), (614, 786), (X0, 786)])
k.t(X0 + 10, 696, "ATTACK RUN", 13, GR)
k.t(X0 + 10, 718, "DIVE   -12°", 12, WH, mono=True)
k.t(X0 + 10, 736, "CLOSE  18 M/S", 12, WH, mono=True)
k.t(X0 + 10, 754, "TTT    2.3 s", 12, YL, mono=True)
k.t(X0 + 170, 718, "ENERGY", 11, GD, mono=True); k.bar(X0 + 170, 734, 120, 10, 0.65, GR, 8)
k.t(X0 + 170, 754, "G 1.2", 12, WH, mono=True)

# ---- bottom centre: weapon rack -------------------------------------------
def tile(x, y, w, h, label, sub, sel):
    pts = [(x + 12, y), (x + w, y), (x + w - 12, y + h), (x, y + h)]
    d.polygon(pts, fill=GR + (235,) if sel else PANEL)
    k.line(pts + [pts[0]], GR, 2)
    col = (0, 0, 0) if sel else WH
    d.text((x + w / 2, y + 6), label, font=font(15), fill=col, anchor="ma")
    d.text((x + w / 2, y + 26), sub, font=font(11, True), fill=(0, 30, 0) if sel else GD, anchor="ma")


tile(CX - 160, 712, 150, 46, "TWIN GUNS", "L + R PODS", True)
tile(CX + 6, 712, 150, 46, "MODE", "AUTO / BURST", False)
k.t(CX, 766, "[LMB] FIRE    [B] MODE", 11, WH, "ma", mono=True)

# ---- bottom right: sprite with pod status ----------------------------------
panel([(1500, 650), (X1, 650), (X1, 790), (1476, 790), (1476, 674)])
d.rectangle((1580, 654, X1 - 4, 786), fill=(4, 18, 8, 255))
k.paste_sprite("grf_sprite.png", 1588, 652, GR, 0.95)
k.t(1488, 660, "AIRFRAME", 11, GD, mono=True)
k.t(1488, 674, "100%", 18, GR)
k.t(1488, 706, "L POD", 11, GD, mono=True); k.bar(1488, 720, 80, 8, 1.0, GR, 5)
k.t(1488, 736, "R POD", 11, GD, mono=True); k.bar(1488, 750, 80, 8, 0.6, YL, 5)

# dim outside the goggle area
d.rectangle((0, 0, X0 - 12, H), fill=(0, 0, 0, 120))
d.rectangle((X1 + 12, 0, W, H), fill=(0, 0, 0, 120))
scanlines(im, 12, 2)
k.d = ImageDraw.Draw(im, "RGBA")
d = k.d
k.note(680, 70, "1 Militech stencil + hazard flashes")
k.note(1150, 262, "2 gun pipper: L/R gun pod heat arcs")
k.note(420, 262, "3 roll wings are the only attitude cue")
k.note(1240, 560, "4 lock diamond + lock %, gun lead marker")
k.note(1180, 380, "5 incoming-fire chevrons on the ring")
k.note(290, 662, "6 attack run: dive, closure, time to target")
k.note(1180, 690, "7 weapon + fire mode")
k.note(1060, 120, "8 kill tally + threat count")
im.save(out("griffin_assault_hud_mockup.png"))
print(out("griffin_assault_hud_mockup.png"))
print("ok")
