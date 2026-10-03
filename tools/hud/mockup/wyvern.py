import math
from PIL import Image, ImageDraw
from kit import Kit, scanlines, font, shot, out

im = shot("wyv_base.png", (2000, 838))
# recon optic: slight desaturated, cool sensor grade
gray = im.convert("L").convert("RGB")
im = Image.blend(im, gray, 0.35)
AM = (255, 182, 60)
WH = (238, 240, 236)
DIM = (175, 170, 160)
RD = (255, 70, 60)
k = Kit(im, AM)
d = k.d
W, H = im.size
X0, X1 = 255, 1745
CX, CY = 1000, 419

# ---- top left: identity, sensor ---------------------------------------------
k.corners(300, 30, 590, 118, 10, AM)
k.t(312, 38, "MILITECH WYVERN // RECON", 16)
k.t(312, 60, "SENSOR  EO-DAY", 12, DIM, mono=True)
k.t(312, 76, "ZOOM    x4.0", 12, WH, mono=True)
k.t(312, 92, "LINK", 12, DIM, mono=True); k.bar(360, 93, 90, 9, 0.95)
k.t(458, 92, "96%  0.21 KM", 12, WH, mono=True)

# ---- top centre: heading tape -----------------------------------------------
hdg = 176
k.line([(CX - 200, 66), (CX + 200, 66)], WH, 1)
for deg in range(hdg - 36, hdg + 37):
    x = CX + (deg - hdg) * 5.5
    if deg % 10 == 0:
        k.line([(x, 58), (x, 66)], WH, 2)
        lab = {0: "N", 90: "E", 180: "S", 270: "W"}.get(deg % 360, str((deg % 360) // 10).zfill(2))
        k.t(x, 40, lab, 12, AM if lab in "NESW" else WH, "ma")
    elif deg % 5 == 0:
        k.line([(x, 62), (x, 66)], WH, 1)
d.polygon([(CX - 6, 78), (CX + 6, 78), (CX, 69)], fill=AM)
k.t(CX, 82, f"{hdg:03d}", 14, WH, "ma")

# ---- top right: record, intel tally, signature ------------------------------
k.corners(1410, 30, 1700, 136, 10, AM)
d.ellipse((1424, 41, 1436, 53), fill=RD)
k.t(1444, 38, "REC  00:02:41", 14, WH, mono=True)
k.t(1424, 62, "TAGGED", 12, DIM, mono=True); k.t(1530, 60, "3", 16, AM)
k.t(1560, 62, "SEEN", 12, DIM, mono=True); k.t(1640, 60, "5", 16, WH)
k.t(1424, 86, "SIGNATURE", 12, DIM, mono=True)
k.bar(1424, 104, 150, 10, 0.25, AM, 6)
k.t(1584, 102, "HIDDEN", 13, AM)

# ---- centre: viewfinder ------------------------------------------------------
fx0, fy0, fx1, fy1 = CX - 150, CY - 90, CX + 150, CY + 90
k.corners(fx0, fy0, fx1, fy1, 22, WH, 2)
for a, b in [((-18, 0), (-6, 0)), ((6, 0), (18, 0)), ((0, -18), (0, -6)), ((0, 6), (0, 18))]:
    k.line([(CX + a[0], CY + a[1]), (CX + b[0], CY + b[1])], WH, 1)
# zoom ladder right of the viewfinder
zx = fx1 + 18
for i, z in enumerate(("x8", "x4", "x2", "x1")):
    y = fy0 + 16 + i * 50
    k.line([(zx, y), (zx + 10, y)], WH, 2)
    k.t(zx + 16, y - 8, z, 12, AM if z == "x4" else DIM, mono=True)
k.line([(zx, fy0 + 16), (zx, fy0 + 166)], WH, 1)
d.polygon([(zx - 4, fy0 + 66), (zx - 14, fy0 + 60), (zx - 14, fy0 + 72)], fill=AM)
k.t(CX, fy1 + 10, "RNG 47 M   ELEV -3.1 M", 13, WH, "ma", mono=True)

# speed / height as small corner readouts on the viewfinder
k.t(fx0 - 14, fy0 + 4, "SPD", 11, DIM, "ra", mono=True)
k.t(fx0 - 14, fy0 + 18, "3 KM/H", 16, WH, "ra")
k.t(fx0 - 14, fy1 - 36, "ALT", 11, DIM, "ra", mono=True)
k.t(fx0 - 14, fy1 - 22, "4.6 M", 16, WH, "ra")


# ---- contact tags in the scene ----------------------------------------------
def tag(x, y, kind, dist, tagged, left=False):
    col = {"HOSTILE": RD, "CIV": DIM, "UNK": AM}[kind]
    r = 9
    pts = [(x, y - r), (x + r, y), (x, y + r), (x - r, y)]
    d.polygon(pts, outline=(0, 0, 0), width=4)
    d.polygon(pts, outline=col, width=2)
    if tagged:
        d.polygon([(x, y - 4), (x + 4, y), (x, y + 4), (x - 4, y)], fill=col)
    sg = -1 if left else 1
    k.line([(x + sg * r, y - r), (x + sg * 22, y - 22), (x + sg * 90, y - 22)], col, 1)
    an = "ra" if left else "la"
    k.t(x + sg * 24, y - 40, f"{kind} {dist}M", 12, col, an, mono=True)
    if tagged:
        k.t(x + sg * 24, y - 20, "TAGGED > V", 10, col, an, mono=True)


tag(1605, 625, "HOSTILE", 63, True, left=True)
tag(1215, 470, "UNK", 52, False)
# edge arrows for contacts outside the feed
for (y, col, s) in [(505, DIM, "CIV 41"), (500, RD, "HOST 70")]:
    pass
d.rectangle((0, 0, X0 - 1, H), fill=(0, 0, 0, 110))
d.rectangle((X1 + 1, 0, W, H), fill=(0, 0, 0, 110))
d.polygon([(X0 + 6, 505), (X0 + 20, 497), (X0 + 20, 513)], fill=DIM)
k.t(X0 + 26, 498, "CIV 41M", 11, DIM, mono=True)
d.polygon([(X1 - 6, 500), (X1 - 20, 492), (X1 - 20, 508)], fill=RD)
k.t(X1 - 26, 493, "HOSTILE 70M", 11, RD, "ra", mono=True)

# ---- lower left: scan scope (top-down) ---------------------------------------
sx, sy, R = 420, 660, 92
d.ellipse((sx - R, sy - R, sx + R, sy + R), fill=(10, 8, 4, 150))
for rr in (R, R * 0.66, R * 0.33):
    k.arc(sx, sy, rr, 0, 360, AM if rr == R else (150, 110, 40), 1 if rr != R else 2)
k.line([(sx - R, sy), (sx + R, sy)], (120, 90, 40), 1)
k.line([(sx, sy - R), (sx, sy + R)], (120, 90, 40), 1)
# camera FOV cone (forward = up)
d.polygon([(sx, sy), (sx - 34, sy - R + 6), (sx + 34, sy - R + 6)], fill=AM + (40,))
# sweep wedge
d.pieslice((sx - R, sy - R, sx + R, sy + R), -60, -20, fill=AM + (70,))
k.line([(sx, sy), (sx + R * math.cos(math.radians(-20)), sy + R * math.sin(math.radians(-20)))], AM, 1)
# contacts
for (ang, frac, col) in [(-20, 0.63, RD), (5, 0.70, RD), (-150, 0.41, DIM), (-80, 0.52, AM), (150, 0.3, DIM)]:
    a = math.radians(ang - 90)
    px, py = sx + math.cos(a) * R * frac, sy + math.sin(a) * R * frac
    d.ellipse((px - 4, py - 4, px + 4, py + 4), fill=col, outline=(0, 0, 0))
# V marker
a = math.radians(160 - 90)
vx, vy = sx + math.cos(a) * R * 0.15, sy + math.sin(a) * R * 0.15
d.polygon([(vx, vy - 7), (vx + 6, vy + 5), (vx - 6, vy + 5)], fill=(90, 220, 255), outline=(0, 0, 0))
d.polygon([(sx, sy - 6), (sx + 5, sy + 5), (sx - 5, sy + 5)], fill=WH)
k.t(sx - R, sy - R - 20, "SCAN 100 M", 12, AM, mono=True)
k.t(sx + R + 16, sy - 30, "V  15 M", 14, (90, 220, 255))
k.t(sx + R + 16, sy - 10, "BRG 196", 11, DIM, mono=True)
k.t(sx + R + 16, sy + 8, "IN RANGE", 11, AM, mono=True)

# ---- bottom centre: recon actions --------------------------------------------
k.t(CX, 718, "[LMB] TAG     [RMB] ZOOM     [B] SCAN PULSE", 13, WH, "ma", mono=True)
k.t(CX - 150, 744, "PULSE", 11, DIM, mono=True)
k.bar(CX - 100, 745, 200, 9, 0.7, AM, 12)
k.t(CX + 110, 742, "4s", 12, WH, mono=True)

# ---- bottom right: airframe sprite ------------------------------------------
d.rectangle((1578, 640, 1708, 826), fill=(8, 8, 8, 235))

k.paste_sprite("wyv_sprite.png", 1592, 650, AM)
k.t(1642, 812, "AIRFRAME 100%", 12, WH, "ma")

scanlines(im, 16)
k.d = ImageDraw.Draw(im, "RGBA")
# ---- callouts ---------------------------------------------------------------
k.note(320, 140, "1 sensor + zoom level")
k.note(1180, 180, "2 viewfinder + zoom ladder, no horizon")
k.note(1250, 540, "3 contact tags: hostile/civ/unknown, tagged ones ping V")
k.note(1450, 150, "4 tag tally + how visible the drone is")
k.note(540, 590, "5 scan scope: contacts, V, camera cone")
k.note(1060, 760, "6 recon actions + scan pulse cooldown")
k.note(1250, 690, "7 sprite (thrusters to be re-scanned)")
im.save(out("wyvern_recon_hud_mockup.png"))
print(out("wyvern_recon_hud_mockup.png"))
print("ok")
