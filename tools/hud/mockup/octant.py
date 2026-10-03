import math
from PIL import Image, ImageDraw
from kit import Kit, scanlines, font, shot, out

im = shot("oct_base.png", (2000, 936))
GR = (120, 255, 130)
GD = (70, 160, 90)
WH = (236, 246, 236)
AM = (255, 176, 60)
RD = (255, 64, 56)
PANEL = (2, 20, 8, 150)
k = Kit(im, GR)
d = k.d
W, H = im.size
CX, CY = 1015, 478


def box(x0, y0, x1, y1, fill=PANEL):
    d.rectangle((x0, y0, x1, y1), fill=fill)
    d.rectangle((x0, y0, x1, y1), outline=(0, 0, 0, 200), width=3)
    d.rectangle((x0, y0, x1, y1), outline=GR, width=1)


# ---- top left: platform + sensor -------------------------------------------
box(16, 16, 360, 120)
k.t(26, 22, "ZETATECH OCTANT // GUNSHIP", 16)
k.t(26, 46, "MTS   DAY-TV   NFOV 4.2°", 12, GR, mono=True)
k.t(26, 64, "LINK  C-BAND", 12, GD, mono=True); k.bar(140, 65, 100, 9, 0.98, GR)
k.t(250, 64, "98%  0.05KM", 12, WH, mono=True)
k.t(26, 82, "LASER ", 12, GD, mono=True); k.t(86, 82, "ARMED", 12, AM, mono=True)
k.t(160, 82, "AUTOTRACK  OFF", 12, GD, mono=True)
k.t(26, 100, "REC ●  02OCT77 07:44:30Z", 12, WH, mono=True)

# ---- top centre: heading tape + gunship banner -----------------------------
hdg = 19
d.rectangle((CX - 34, 22, CX + 34, 50), fill=PANEL, outline=GR, width=2)
k.t(CX, 24, f"{hdg:03d}", 20, WH, "ma")
k.line([(CX - 260, 72), (CX + 260, 72)], GR, 1)
for deg in range(hdg - 45, hdg + 46):
    x = CX + (deg - hdg) * 5.7
    if deg % 10 == 0:
        k.line([(x, 62), (x, 72)], GR, 2)
        lab = {0: "N", 90: "E", 180: "S", 270: "W"}.get(deg % 360, str((deg % 360) // 10).zfill(2))
        k.t(x, 76, lab, 11, GR, "ma", mono=True)
    elif deg % 5 == 0:
        k.line([(x, 67), (x, 72)], GR, 1)
d.polygon([(CX, 56), (CX - 6, 50), (CX + 6, 50)], fill=GR)
box(CX - 190, 100, CX + 190, 124, fill=(40, 26, 0, 150))
k.t(CX, 104, "GUNSHIP // HOLDING   ORBIT L 40M   [H] RELEASE", 12, AM, "ma", mono=True)

# ---- top right: target data -------------------------------------------------
box(1640, 16, 1984, 120)
k.t(1650, 22, "TARGET", 14, GR)
k.t(1650, 44, "SLANT   0028 M", 13, WH, mono=True)
k.t(1650, 62, "BRG     019", 13, WH, mono=True)
k.t(1650, 80, "ΔH      -14 M", 13, WH, mono=True)
k.t(1650, 98, "TGT SPD 00 KM/H", 13, WH, mono=True)
k.t(1974, 22, "STATIC", 12, AM, "ra", mono=True)

# ---- centre: MTS reticle ----------------------------------------------------
gap, arm = 34, 230
for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
    a = (CX + dx * gap, CY + dy * gap)
    b = (CX + dx * (arm if dx else arm * 0.6), CY + dy * (arm if dx else arm * 0.6))
    k.line([a, b], WH, 1)
    n = 6 if dx else 4
    for i in range(1, n + 1):
        f = gap + (abs(b[0] - CX) + abs(b[1] - CY) - gap) * i / n
        px, py = CX + dx * f, CY + dy * f
        if dx:
            k.line([(px, py - 5), (px, py + 5)], WH, 1)
        else:
            k.line([(px - 5, py), (px + 5, py)], WH, 1)
k.corners(CX - 18, CY - 18, CX + 18, CY + 18, 7, GR, 2)
d.ellipse((CX - 2, CY - 2, CX + 2, CY + 2), fill=GR)
k.t(CX, CY + 156, "LRF 0028 M", 15, GR, "ma", mono=True)
d.rectangle((CX + 70, CY + 154, CX + 90, CY + 174), fill=AM)
d.text((CX + 80, CY + 156), "L", font=font(15, True), fill=(0, 0, 0), anchor="ma")
k.t(CX + 96, CY + 158, "LASING", 11, AM, mono=True)

# depression-angle scale (gunship looking down), right of the reticle
ax, ay, ar = CX + 300, CY - 120, 90
k.arc(ax, ay, ar, 90, 180, GD, 1)
for deg in range(0, 91, 15):
    t = math.radians(180 - deg)
    k.line([(ax + math.cos(t) * ar, ay + math.sin(t) * ar), (ax + math.cos(t) * (ar - 8), ay + math.sin(t) * (ar - 8))], GR, 2)
dep = 38
t = math.radians(180 - dep)
d.polygon([(ax + math.cos(t) * (ar + 2), ay + math.sin(t) * (ar + 2)),
           (ax + math.cos(t + 0.12) * (ar + 14), ay + math.sin(t + 0.12) * (ar + 14)),
           (ax + math.cos(t - 0.12) * (ar + 14), ay + math.sin(t - 0.12) * (ar + 14))], fill=GR)
k.t(ax - ar - 4, ay - 18, "DEP 38°", 12, GR, "ra", mono=True)


# ---- speed + altitude tapes (kept, tighter) ---------------------------------
def tape(x, val, label, right):
    top, bot = CY - 150, CY + 150
    k.line([(x, top), (x, bot)], GR, 2)
    for i in range(-7, 8):
        y = CY + i * 20
        ln = 12 if i % 2 == 0 else 6
        k.line([(x, y), (x + (-ln if right else ln), y)], GR, 2)
    bw = 86
    x0 = x + 8 if right else x - 8 - bw
    box(x0, CY - 15, x0 + bw, CY + 15)
    k.t(x0 + bw - 8, CY - 12, val, 20, WH, "ra")
    k.t(x, top - 20, label, 11, GD, "ma", mono=True)


tape(CX - 470, "0.0", "M/S", False)
tape(CX + 470, "016", "ALT M", True)
k.t(CX + 470 + 50, CY + 22, "VS +0.0", 12, WH, "ma", mono=True)

# ---- mortar splash prediction around the game's impact marker --------------
mx, my, rx, ry = 494, 738, 120, 46
for a0 in range(0, 360, 14):
    d.arc((mx - rx, my - ry, mx + rx, my + ry), a0, a0 + 8, fill=(0, 0, 0, 180), width=4)
    d.arc((mx - rx, my - ry, mx + rx, my + ry), a0, a0 + 8, fill=AM, width=2)
k.line([(mx + rx - 10, my - ry + 6), (mx + rx + 30, my - ry - 30), (mx + rx + 150, my - ry - 30)], AM, 1)
k.t(mx + rx + 34, my - ry - 50, "MORTAR x4  SPREAD 6M", 12, AM, mono=True)
k.t(mx + rx + 34, my - ry - 26, "TOF 3.1 s", 12, WH, mono=True)

# ---- bottom left: situation display (top-down) ------------------------------
sx0, sy0, sx1, sy1 = 16, 520, 300, 740
box(sx0, sy0, sx1, sy1, fill=(2, 14, 6, 190))
k.t(sx0 + 8, sy0 + 6, "SITUATION", 11, GD, mono=True)
k.t(sx1 - 8, sy0 + 6, "N↑  100 M", 11, GD, "ra", mono=True)
scx, scy = (sx0 + sx1) // 2, (sy0 + sy1) // 2 + 10
for rr in (80, 40):
    d.ellipse((scx - rr, scy - rr, scx + rr, scy + rr), outline=(60, 120, 70), width=1)
# orbit
for a0 in range(0, 360, 20):
    d.arc((scx - 40, scy - 40, scx + 40, scy + 40), a0, a0 + 10, fill=AM, width=2)
# sensor footprint trapezoid (looking NNE)
hd = math.radians(hdg - 90)
fx, fy = scx + math.cos(hd) * 62, scy + math.sin(hd) * 62
nx, ny = -math.sin(hd), math.cos(hd)
fp = [(scx + nx * 6, scy + ny * 6), (scx - nx * 6, scy - ny * 6), (fx - nx * 24, fy - ny * 24), (fx + nx * 24, fy + ny * 24)]
d.polygon(fp, fill=GR + (60,), outline=GR)
d.polygon([(scx, scy - 7), (scx + 6, scy + 6), (scx - 6, scy + 6)], fill=WH, outline=(0, 0, 0))
d.polygon([(fx, fy - 6), (fx + 6, fy), (fx, fy + 6), (fx - 6, fy)], fill=RD)
vx, vy = scx - 50, scy + 46
d.ellipse((vx - 5, vy - 5, vx + 5, vy + 5), fill=(90, 220, 255), outline=(0, 0, 0))
k.t(vx + 8, vy - 6, "V", 11, (90, 220, 255), mono=True)
k.t(fx + 10, fy - 8, "TGT", 11, RD, mono=True)

# ---- bottom left: stores page ------------------------------------------------
box(16, 752, 360, 918, fill=(2, 14, 6, 190))
k.t(26, 758, "STORES", 11, GD, mono=True)
k.t(350, 758, "MASTER ARM ON", 11, AM, "ra", mono=True)
rows = [("1", "MORTAR", "x4  UNLTD", "RDY", True), ("2", "ROCKETS", "4 / 4", "RDY", False),
        ("3", "LMG x2", "HEAT 0%", "RDY", False)]
for i, (sta, name, sub, st, sel) in enumerate(rows):
    y = 780 + i * 36
    if sel:
        d.rectangle((22, y - 2, 354, y + 28), fill=GR + (220,))
        col, sc = (0, 0, 0), (0, 40, 0)
    else:
        col, sc = WH, GD
    d.text((30, y + 4), f"STA{sta}", font=font(12, True), fill=sc)
    d.text((86, y + 2), name, font=font(16), fill=col)
    d.text((196, y + 4), sub, font=font(12, True), fill=sc if not sel else (0, 40, 0))
    d.text((346, y + 4), st, font=font(12, True), fill=col if sel else GR, anchor="ra")
k.t(26, 892, "[B] STA  [LMB] FIRE  [G] MISSILE  [RMB] ZOOM  [T] SENSOR", 10, GD, mono=True)

# ---- bottom right: airframe -------------------------------------------------
box(1800, 670, 1984, 918, fill=(2, 14, 6, 200))
k.t(1810, 676, "AIRFRAME", 11, GD, mono=True)
k.paste_sprite("oct_sprite.png", 1840, 690, GR, 0.95)
d.rectangle((1804, 880, 1980, 914), fill=(2, 14, 6, 255))
k.t(1810, 892, "HULL 99%   THR 4/4", 12, WH, mono=True)

scanlines(im, 12, 2)
k.d = ImageDraw.Draw(im, "RGBA")
k.note(370, 30, "1 sensor ball, laser + record line")
k.note(1200, 150, "2 gunship banner with orbit")
k.note(1420, 130, "3 target data block")
k.note(1080, 700, "4 MTS crosshair + laser 'L' cue")
k.note(1290, 270, "5 look-down angle")
k.note(700, 700, "6 mortar spread + time of flight")
k.note(310, 528, "7 situation map: orbit, sensor footprint, V")
k.note(370, 760, "8 stores page: stations, master arm")
im.save(out("octant_gunship_hud_mockup.png"))
print(out("octant_gunship_hud_mockup.png"))
print("ok")
