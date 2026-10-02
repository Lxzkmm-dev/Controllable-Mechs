# The drone HUDs' shape kit: smooth, anti-aliased white shapes in one atlas, drawn by the
# HUDs as tinted images (ink draws only rectangles; a meter, a dot or a ring built from
# rectangles reads as blocks, Omar). Pills nine-slice to any length with round caps,
# rounded panels nine-slice to any size; rings and discs scale.
#
# Usage: python uikit.py <turret_hud.inkatlas.json> <raw out folder>
# Writes <out>/mnc/hud/ui_kit.png (premultiplied alpha: rgb = alpha, the game's UI
# convention), <out>/mnc/hud/ui_kit.inkatlas.json, and prints each part's nine-slice grid.
# Standard library only.
import json, math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "drones"))
from scan import png  # noqa: E402

AW, AH = 1024, 1024


def clamp(v):
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def cov(sd):
    # coverage of a pixel from the signed distance to an edge (negative inside)
    return clamp(0.5 - sd)


def sd_capsule(x, y, w, h):
    # a horizontal capsule filling w x h (radius h / 2)
    r = h / 2.0
    cx = min(max(x, r), w - r)
    return math.hypot(x - cx, y - r) - r


def sd_rrect(x, y, w, h, r):
    qx = abs(x - w / 2.0) - (w / 2.0 - r)
    qy = abs(y - h / 2.0) - (h / 2.0 - r)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def shape(w, h, f):
    # f(px centre x, y) -> alpha 0-1, sampled 4x4 per pixel where it matters
    out = []
    for j in range(h):
        row = []
        for i in range(w):
            a = f(i + 0.5, j + 0.5)
            row.append(a)
        out.append(row)
    return out


def tri_sd(x, y, w, h):
    # an upward triangle filling the box: the max of its three edge distances
    ax, ay, bx, by, cx, cy = w / 2.0, 1.0, w - 1.0, h - 1.0, 1.0, h - 1.0
    def edge(px, py, qx, qy):
        nx, ny = qy - py, -(qx - px)
        l = math.hypot(nx, ny)
        return ((x - px) * nx + (y - py) * ny) / l
    return max(edge(ax, ay, bx, by), edge(bx, by, cx, cy), edge(cx, cy, ax, ay))


def parts():
    P = {}
    # pills: horizontal and vertical, round caps; nine-slice keeps the caps
    P["pill_h"] = (shape(64, 16, lambda x, y: cov(sd_capsule(x, y, 64, 16))), (8, 0, 8, 0))
    P["pill_v"] = (shape(16, 64, lambda x, y: cov(sd_capsule(y, x, 64, 16))), (0, 8, 0, 8))
    P["pill_line_h"] = (shape(64, 16, lambda x, y: cov(abs(sd_capsule(x, y, 64, 16) + 1.0) - 1.0)), (8, 0, 8, 0))
    # a soft glow under a pill
    P["pill_glow_h"] = (shape(96, 40, lambda x, y: clamp(1.0 - max(0.0, sd_capsule(x - 16, y - 12, 64, 16)) / 12.0) ** 2 * 0.8), (28, 0, 28, 0))
    # rounded panels: glass fill and a thin line, 12 px corners
    P["rrect_fill"] = (shape(48, 48, lambda x, y: cov(sd_rrect(x, y, 48, 48, 12))), (14, 14, 14, 14))
    P["rrect_line"] = (shape(48, 48, lambda x, y: cov(abs(sd_rrect(x, y, 48, 48, 12) + 1.25) - 1.25)), (14, 14, 14, 14))
    P["rrect_fill_s"] = (shape(24, 24, lambda x, y: cov(sd_rrect(x, y, 24, 24, 6))), (7, 7, 7, 7))
    P["rrect_line_s"] = (shape(24, 24, lambda x, y: cov(abs(sd_rrect(x, y, 24, 24, 6) + 1.0) - 1.0)), (7, 7, 7, 7))
    # discs and rings
    P["disc"] = (shape(64, 64, lambda x, y: cov(math.hypot(x - 32, y - 32) - 30.5)), None)
    P["dot_glow"] = (shape(64, 64, lambda x, y: clamp(1.0 - math.hypot(x - 32, y - 32) / 31.0) ** 2), None)
    for name, size, stroke in (("ring_s", 64, 4.0), ("ring_m", 256, 4.0), ("ring_l", 512, 5.0)):
        c = size / 2.0
        r = c - stroke / 2.0 - 1.0
        P[name] = (shape(size, size, lambda x, y, c=c, r=r, s=stroke: cov(abs(math.hypot(x - c, y - c) - r) - s / 2.0)), None)
    # pointers
    P["tri"] = (shape(64, 64, lambda x, y: cov(tri_sd(x, y, 64, 64))), None)
    P["diamond"] = (shape(64, 64, lambda x, y: cov((abs(x - 32) + abs(y - 32) - 30) / 1.4142)), None)
    P["diamond_line"] = (shape(64, 64, lambda x, y: cov(abs((abs(x - 32) + abs(y - 32) - 28) / 1.4142) - 2.0)), None)
    def chev(x, y):
        # an up chevron: two strokes 6 px wide meeting at the top
        d1 = abs((x - 32) * 0.6 + (y - 8) * 0.8) if x < 32 else 99
        def seg(px, py, qx, qy):
            vx, vy = qx - px, qy - py
            t = max(0.0, min(1.0, ((x - px) * vx + (y - py) * vy) / (vx * vx + vy * vy)))
            return math.hypot(x - (px + vx * t), y - (py + vy * t))
        return cov(min(seg(6, 34, 32, 8), seg(32, 8, 58, 34)) - 3.5)
    P["chevron"] = (shape(64, 40, chev), None)

    def seg(x, y, px, py, qx, qy):
        vx, vy = qx - px, qy - py
        t = max(0.0, min(1.0, ((x - px) * vx + (y - py) * vy) / (vx * vx + vy * vy)))
        return math.hypot(x - (px + vx * t), y - (py + vy * t))
    # bracket corners (top-left; the HUDs turn them for the others), round-ended: a light one
    # for small brackets and a thin one drawn larger for big frames
    for name, size, s in (("corner", 32, 4.0), ("corner_l", 128, 5.0)):
        h = s / 2.0 + 0.5
        P[name] = (shape(size, size, lambda x, y, size=size, h=h, s=s: cov(min(seg(x, y, h, h, size - h, h), seg(x, y, h, h, h, size - h)) - s / 2.0)), None)
    # the Griffin's banner: a trapezoid, wide at the top, slanted ends; fill and line
    def trap_sd(x, y, w, hgt, sl):
        def edge(px, py, qx, qy):
            nx, ny = qy - py, -(qx - px)
            l = math.hypot(nx, ny)
            return ((x - px) * nx + (y - py) * ny) / l
        pts = [(1.0, 1.0), (w - 1.0, 1.0), (w - 1.0 - sl, hgt - 1.0), (1.0 + sl, hgt - 1.0)]
        return max(edge(*pts[i], *pts[(i + 1) % 4]) for i in range(4))
    P["banner_fill"] = (shape(192, 64, lambda x, y: cov(trap_sd(x, y, 192, 64, 48))), (60, 0, 60, 0))
    P["banner_line"] = (shape(192, 64, lambda x, y: cov(abs(trap_sd(x, y, 192, 64, 48) + 1.5) - 1.5)), (60, 0, 60, 0))
    # an edge fade: opaque at the top, gone at the bottom (vignettes, turned for each edge)
    P["fade"] = (shape(8, 64, lambda x, y: (1.0 - y / 64.0) ** 2), (0, 0, 0, 0))
    return P


def main():
    ref_json, out = sys.argv[1:3]
    P = parts()
    atlas = bytearray(AW * AH * 4)
    placed = {}
    x = y = shelf = 0
    for name, (img, grid) in sorted(P.items(), key=lambda kv: -len(kv[1][0])):
        h = len(img); w = len(img[0])
        if x + w + 4 > AW:
            x = 0; y += shelf + 4; shelf = 0
        assert y + h <= AH
        for j in range(h):
            for i in range(w):
                v = int(round(clamp(img[j][i]) * 255))
                o = ((y + j) * AW + x + i) * 4
                atlas[o:o + 4] = bytes((v, v, v, v))
        placed[name] = (x, y, w, h, grid)
        x += w + 4
        shelf = max(shelf, h)
    depot = "mnc/hud/ui_kit"
    os.makedirs(os.path.join(out, os.path.dirname(depot)), exist_ok=True)
    png(os.path.join(out, depot + ".png"), AW, AH, atlas)
    ref = json.load(open(ref_json, encoding="utf-8"))
    root = ref["Data"]["RootChunk"]
    mappers = []
    for name, (px, py, w, h, grid) in placed.items():
        mappers.append({"$type": "inkTextureAtlasMapper",
                        "clippingRectInPixels": {"$type": "Rect", "bottom": 0, "left": 0, "right": 0, "top": 0},
                        "clippingRectInUVCoords": {"$type": "RectF", "Bottom": (py + h) / AH, "Left": px / AW, "Right": (px + w) / AW, "Top": py / AH},
                        "partName": {"$type": "CName", "$storage": "string", "$value": name}})
    tex = {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": depot.replace("/", "\\") + ".xbm"}, "Flags": "Default"}
    for slot in root["slots"]["Elements"]:
        slot["parts"] = mappers
        slot["texture"] = json.loads(json.dumps(tex))
    root["textureResolution"] = "UltraHD_3840_2160"
    ref["Header"]["ArchiveFileName"] = depot.replace("/", "\\") + ".inkatlas"
    json.dump(ref, open(os.path.join(out, depot + ".inkatlas.json"), "w", encoding="utf-8"), indent=2)
    for name, (px, py, w, h, grid) in sorted(placed.items()):
        print(name, w, h, grid)


if __name__ == "__main__":
    main()
