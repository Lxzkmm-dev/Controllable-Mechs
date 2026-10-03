import math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

from kit import shot, out, font

OUT = out("bombus_hud_mockup_v2.png")
random.seed(7)

# raw a37 Bombus screenshot; the boxes below inpaint its old HUD away
im = shot("bombus_raw.png", (2000, 813))
W, H = im.size
px = im.load()


def inpaint(x0, y0, x1, y1):
    # vertical blend between the rows just outside the box (crude, mockup only)
    for x in range(x0, x1):
        a = px[x, max(y0 - 1, 0)]
        b = px[x, min(y1, H - 1)]
        for y in range(y0, y1):
            t = (y - y0) / max(1, (y1 - y0))
            px[x, y] = tuple(int(a[i] * (1 - t) + b[i] * t + random.randint(-3, 3)) for i in range(3))


# remove the a37 HUD (keep the sprite, it is reused)
for box in [(0, 12, 215, 92), (1890, 15, 1975, 92), (640, 402, 1360, 452),
            (900, 698, 1105, 778), (40, 760, 125, 790)]:
    inpaint(*box)

im = im.filter(ImageFilter.SMOOTH) if False else im
d = ImageDraw.Draw(im, "RGBA")

f = {s: font(s, True) for s in (11, 13, 15, 18, 22, 26, 30)}
CY = (41, 214, 236)
WH = (240, 246, 248)
AM = (255, 176, 40)
RD = (255, 60, 60)
DIM = (150, 170, 175)


def txt(x, y, s, size=15, col=WH, anchor="la"):
    d.text((x, y), s, font=f[size], fill=col, anchor=anchor, stroke_width=2, stroke_fill=(0, 0, 0))


def bar(x, y, w, h, frac, col=CY, segs=10):
    d.rectangle((x, y, x + w, y + h), outline=(0, 0, 0, 200), width=3)
    d.rectangle((x, y, x + w, y + h), outline=WH, width=1)
    sw = (w - 2) / segs
    for i in range(segs):
        if (i + 0.5) / segs <= frac:
            d.rectangle((x + 2 + i * sw, y + 2, x + (i + 1) * sw - 1, y + h - 2), fill=col + (230,))


def line(pts, col=WH, w=2):
    d.line(pts, fill=(0, 0, 0, 200), width=w + 2)
    d.line(pts, fill=col, width=w)


# ---- top left: identity + power + link -------------------------------------
txt(22, 16, "ZETATECH BOMBUS", 18)
txt(22, 38, "FPV-03 // CH 5.8G R4", 11, DIM)
txt(22, 54, "4S", 15, DIM)
txt(50, 50, "16.5V", 26)
txt(150, 58, "4.12/c", 13, DIM)
for i, v in enumerate((0.84, 0.82, 0.83, 0.80)):
    bar(22 + i * 46, 82, 40, 10, v, CY, 5)
txt(22, 100, "SIG", 11, DIM); bar(56, 101, 90, 9, 0.9)
txt(152, 100, "RSSI 96", 11)
txt(22, 116, "LQ ", 11, DIM); bar(56, 117, 90, 9, 0.97)
txt(152, 116, "LQ 97", 11)
txt(22, 132, "MOT", 11, DIM); bar(56, 133, 90, 9, 0.48, AM)
txt(152, 132, "54°C", 11, AM)
txt(22, 148, "RNG", 11, DIM); txt(56, 148, "0.02 KM  HOME 184°", 11)

# ---- top right: timer, mode, rec ------------------------------------------
txt(1978, 16, "00:19", 26, WH, "ra")
txt(1978, 48, "HORIZON", 15, WH, "ra")
d.ellipse((1906, 70, 1918, 82), fill=RD)
txt(1978, 68, "REC", 13, WH, "ra")
txt(1978, 88, "1080p60 // 28ms", 11, DIM, "ra")

# ---- top centre: compass tape ---------------------------------------------
cx, ty = 1000, 22
hdg = 274
line([(cx - 220, ty + 22), (cx + 220, ty + 22)], WH, 1)
for deg in range(hdg - 40, hdg + 41):
    x = cx + (deg - hdg) * 5.5
    if deg % 10 == 0:
        line([(x, ty + 14), (x, ty + 22)], WH, 2)
        lab = {0: "N", 90: "E", 180: "S", 270: "W"}.get(deg % 360, str((deg % 360) // 10).zfill(2))
        txt(x, ty - 2, lab, 13, CY if lab in "NESW" else WH, "ma")
    elif deg % 5 == 0:
        line([(x, ty + 18), (x, ty + 22)], WH, 1)
d.polygon([(cx - 7, ty + 34), (cx + 7, ty + 34), (cx, ty + 25)], fill=CY)
txt(cx, ty + 38, f"{hdg:03d}", 15, WH, "ma")

# ---- centre: crosshair only ------------------------------------------------
cx, cy = 1000, 420
for a, b in [((-26, 0), (-9, 0)), ((9, 0), (26, 0)), ((0, -14), (0, -6))]:
    line([(cx + a[0], cy + a[1]), (cx + b[0], cy + b[1])], WH, 2)
d.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=WH)

# target brackets on the burning car + range block
tx0, ty0, tx1, ty1 = 942, 448, 1040, 486
L = 12
for (x, y, sx, sy) in [(tx0, ty0, 1, 1), (tx1, ty0, -1, 1), (tx0, ty1, 1, -1), (tx1, ty1, -1, -1)]:
    line([(x, y + sy * L), (x, y), (x + sx * L, y)], AM, 2)
line([(tx1, ty0), (tx1 + 30, ty0 - 22), (tx1 + 120, ty0 - 22)], AM, 1)
txt(tx1 + 34, ty0 - 40, "VEH  38 M", 13, AM)
txt(tx1 + 34, ty0 - 20, "IN BLAST", 11, AM)

# blast footprint ring on the road at the predicted impact point
ex, ey, rx, ry = 990, 472, 120, 22
for k in range(0, 360, 12):
    a0, a1 = math.radians(k), math.radians(k + 7)
    d.arc((ex - rx, ey - ry, ex + rx, ey + ry), k, k + 7, fill=(0, 0, 0, 180), width=4)
    d.arc((ex - rx, ey - ry, ex + rx, ey + ry), k, k + 7, fill=CY, width=2)
line([(ex - 6, ey), (ex + 6, ey)], CY, 2); line([(ex, ey - 4), (ex, ey + 4)], CY, 2)
txt(ex - rx - 6, ey + 8, "TOX 6M", 11, CY, "ra")

# ---- side readouts (no ladder, no horizon line) ----------------------------
def readout(x, y, label, val, unit, anchor):
    w = 108
    x0 = x if anchor == "l" else x - w
    d.rectangle((x0, y, x0 + w, y + 34), fill=(0, 0, 0, 90), outline=WH, width=1)
    txt(x0 + 6, y - 15, label, 11, DIM)
    txt(x0 + w - 6, y + 4, val, 22, WH, "ra")
    txt(x0 + w + 4 if anchor == "l" else x0 - 4, y + 12, unit, 11, DIM, "la" if anchor == "l" else "ra")

readout(700, 400, "SPD", "0", "KM/H", "l")
readout(1300, 400, "ALT", "4.6", "M", "r")
txt(1300 - 108 + 6, 440, "VS +0.0 M/S", 11, WH)
txt(700 + 6, 440, "GND 4.6 M", 11, WH)

# ---- lower left: attitude gauge + throttle ---------------------------------
gx, gy, R = 110, 650, 62
roll, pitch = math.radians(-8), 6  # mock values
gauge = Image.new("RGBA", (2 * R, 2 * R), (0, 0, 0, 0))
gd = ImageDraw.Draw(gauge)
gd.rectangle((0, 0, 2 * R, 2 * R), fill=(20, 60, 70, 150))
cxg, cyg = R, R + pitch
dx, dy = math.cos(roll) * 3 * R, math.sin(roll) * 3 * R
nx, ny = -math.sin(roll), math.cos(roll)
gd.polygon([(cxg - dx, cyg - dy), (cxg + dx, cyg + dy), (cxg + dx + nx * 3 * R, cyg + dy + ny * 3 * R),
            (cxg - dx + nx * 3 * R, cyg - dy + ny * 3 * R)], fill=(10, 18, 20, 200))
gd.line([(cxg - dx, cyg - dy), (cxg + dx, cyg + dy)], fill=CY, width=2)
for p in (-10, 10):
    ox, oy = cxg - nx * p * 2.2, cyg - ny * p * 2.2
    gd.line([(ox - math.cos(roll) * 14, oy - math.sin(roll) * 14), (ox + math.cos(roll) * 14, oy + math.sin(roll) * 14)],
            fill=(200, 230, 235), width=1)
mask = Image.new("L", (2 * R, 2 * R), 0)
ImageDraw.Draw(mask).ellipse((0, 0, 2 * R - 1, 2 * R - 1), fill=255)
im.paste(gauge, (gx - R, gy - R), Image.composite(gauge, Image.new("RGBA", gauge.size), mask).split()[3])
d = ImageDraw.Draw(im, "RGBA")
d.ellipse((gx - R, gy - R, gx + R, gy + R), outline=(0, 0, 0), width=4)
d.ellipse((gx - R, gy - R, gx + R, gy + R), outline=WH, width=2)
# fixed aircraft symbol
line([(gx - 30, gy), (gx - 10, gy), (gx - 4, gy + 6), (gx, gy), (gx + 4, gy + 6), (gx + 10, gy), (gx + 30, gy)], AM, 2)
# roll arc ticks
for a in (-45, -30, -20, -10, 0, 10, 20, 30, 45):
    t = math.radians(a - 90)
    r1, r2 = R + 4, R + (12 if a % 30 == 0 else 8)
    line([(gx + math.cos(t) * r1, gy + math.sin(t) * r1), (gx + math.cos(t) * r2, gy + math.sin(t) * r2)], WH, 2)
t = roll - math.pi / 2
tipx, tipy = gx + math.cos(t) * (R + 2), gy + math.sin(t) * (R + 2)
d.polygon([(tipx, tipy), (tipx + math.cos(t + 2.7) * 12, tipy + math.sin(t + 2.7) * 12),
           (tipx + math.cos(t - 2.7) * 12, tipy + math.sin(t - 2.7) * 12)], fill=CY)
txt(gx, gy + R + 8, "R -8°  P +3°", 11, WH, "ma")

# throttle: vertical bar right of the gauge
bx, by0, by1 = 196, 592, 712
d.rectangle((bx, by0, bx + 14, by1), outline=(0, 0, 0), width=3)
d.rectangle((bx, by0, bx + 14, by1), outline=WH, width=1)
th = 0.49
d.rectangle((bx + 3, by1 - (by1 - by0) * th, bx + 11, by1 - 3), fill=CY)
txt(bx + 7, by1 + 8, "THR", 11, DIM, "ma")
txt(bx + 7, by0 - 18, "49%", 13, WH, "ma")

# ---- bottom centre: payload + arming --------------------------------------
txt(1000, 676, "PAYLOAD // TOXIC GAS", 15, WH, "ma")
steps = ["SAFE", "ARMING", "ARMED"]
for i, s in enumerate(steps):
    x = 900 + i * 100
    on = True
    d.rectangle((x - 46, 700, x + 46, 722), fill=(CY + (200,)) if i == 2 else (0, 0, 0, 120), outline=WH, width=1)
    if i == 2:
        d.text((x, 704), s, font=f[13], fill=(0, 0, 0), anchor="ma")
    else:
        txt(x, 704, s, 13, DIM, "ma")
txt(1000, 732, "IMPACT  T-02.4s", 18, AM, "ma")
txt(1000, 760, "[LMB] DETONATE", 11, WH, "ma")

# ---- bottom right: sprite frame + motors ----------------------------------
sx0, sy0, sx1, sy1 = 1808, 540, 1960, 690
for (x, y, ax, ay) in [(sx0, sy0, 1, 1), (sx1, sy0, -1, 1), (sx0, sy1, 1, -1), (sx1, sy1, -1, -1)]:
    line([(x, y + ay * 14), (x, y), (x + ax * 14, y)], WH, 2)
txt(sx0, sy0 - 18, "AIRFRAME", 11, DIM)
txt(sx1, sy0 - 18, "HULL 100%", 11, CY, "ra")
for i, (lab, v) in enumerate((("M1", 0.52), ("M2", 0.50), ("M3", 0.55))):
    txt(sx0 - 70, sy0 + 18 + i * 22, lab, 11, DIM)
    bar(sx0 - 48, sy0 + 19 + i * 22, 38, 10, v, CY, 5)
txt(sx0 - 70, sy0 + 86, "RPM 18.2K", 11, WH)

# ---- feed: edge fringing + one glitch band -------------------------------
r, g, b = im.split()
r = ImageChops.offset(r, 2, 0)
b = ImageChops.offset(b, -2, 0)
fr = Image.merge("RGB", (r, g, b))
vign = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(vign)
vd.rectangle((0, 0, W, H), fill=255)
vd.ellipse((-200, -260, W + 200, H + 260), fill=0)
vign = vign.filter(ImageFilter.GaussianBlur(120))
im = Image.composite(fr, im, vign)
band = im.crop((0, 300, W, 306))
im.paste(ImageChops.offset(band, 14, 0), (0, 300))
d = ImageDraw.Draw(im, "RGBA")
for y in range(0, H, 3):
    d.line([(0, y), (W, y)], fill=(0, 0, 0, 22))

# ---- callouts (mockup only) -----------------------------------------------
def note(x, y, s):
    d.rounded_rectangle((x - 4, y - 3, x + 9 * len(s) + 4, y + 17), 4, fill=(255, 0, 140, 210))
    d.text((x, y), s, font=f[13], fill=(255, 255, 255))

note(232, 640, "1 attitude gauge replaces the centre line")
note(1110, 500, "2 target brackets + range")
note(760, 500, "3 blast footprint")
note(250, 100, "4 cells / signal / motor temp")
note(1160, 735, "5 arming + impact countdown")
note(1220, 60, "6 compass tape")
note(1520, 300, "7 colour fringe + glitch grow as link weakens")
im.save(OUT)
print(OUT, im.size)
