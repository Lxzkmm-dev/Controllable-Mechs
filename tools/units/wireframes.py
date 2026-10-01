# Whole-unit wireframes for other mods' UIs (Night City Empires' Mech Bay and dossier cards).
#
# Renders each unit MNC supports (the Minotaur and the four drones) from its real meshes
# (glTF exported by WolvenKit) as a three-quarter front view, 512 x 512, white lines on
# transparent with premultiplied alpha (RGB = alpha) so the UI can tint it, and packs them
# into one 2048 x 1024 atlas with an inkatlas naming the parts (minotaur, bombus, griffin,
# wyvern, octant), from the game's turret_hud.inkatlas as a template.
#
# Usage: python wireframes.py <drones glb folder (raw_<kind>)> <minotaur glb folder>
#                             <turret_hud.inkatlas.json> <raw out folder>
# Standard library only. glTF is Y-up: game (X, Y, Z) = glTF (x, -z, y), forward +Y.
import json, math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "drones"))
from scan import read_glb, png  # noqa: E402

DEPOT = "mnc/ui/unit_wireframes"
CELL = 512
AW, AH = 2048, 1024
YAW, PITCH = 32.0, 16.0   # the camera: front-right of the unit, looking slightly down

UNITS = [
    ("minotaur", None, ["mch_003__minotaur_body_01", "mch_003__minotaur_legs_01", "mch_003__minotaur_arm_l_01", "mch_003__minotaur_arm_r_01",
                        "mch_003__minotaur_hands_01", "mch_003__minotaur_weapons_l_01", "mch_003__minotaur_weapons_r_01", "mch_003__minotaur_bags_01"]),
    ("bombus", "raw_bombus", ["av_zetatech_bombus__ext01_surveillance", "av_zetatech_bombus__ext01_propellers", "av_zetatech_bombus__weapon"]),
    ("griffin", "raw_griffin", ["av_militech_griffin_body_01", "av_militech_griffin_wing_l_01", "av_militech_griffin_wing_r_01"]),
    ("wyvern", "raw_wyvern", ["av_militech_wyvern_01"]),
    ("octant", "raw_octant", ["av_zetatech_octant__ext01_body_01", "av_zetatech_octant__ext01_gun_02"]),
]


def view_basis():
    y, p = math.radians(YAW), math.radians(PITCH)
    c = (math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p))   # toward the camera
    f = (-c[0], -c[1], -c[2])
    r = (f[1] * 1 - f[2] * 0, f[2] * 0 - f[0] * 1, 0.0)                        # f x Z
    n = math.sqrt(r[0] ** 2 + r[1] ** 2)
    r = (r[0] / n, r[1] / n, 0.0)
    u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])
    return r, u, c


def render(tris):
    # hidden lines removed (z-buffer), feature edges only (creases, silhouettes, open
    # boundaries), a faint fill for the body: the same look as the HUD schematic
    r, u, c = view_basis()
    def proj(p):
        return (p[0] * r[0] + p[1] * r[1] + p[2] * r[2], p[0] * u[0] + p[1] * u[1] + p[2] * u[2], -(p[0] * c[0] + p[1] * c[1] + p[2] * c[2]))
    vt = [tuple(proj(p) for p in t) for t in tris]
    xs = [q[0] for t in vt for q in t]
    ys = [q[1] for t in vt for q in t]
    span = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.06
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    k = (CELL - 1) / span
    def scr(q):
        return ((q[0] - cx) * k + CELL / 2, (cy - q[1]) * k + CELL / 2, q[2])
    st = [tuple(scr(q) for q in t) for t in vt]
    INF = 1e9
    zbuf = [INF] * (CELL * CELL)
    for a, b, cc in st:
        x0 = max(0, int(min(a[0], b[0], cc[0]))); x1 = min(CELL - 1, int(max(a[0], b[0], cc[0])) + 1)
        y0 = max(0, int(min(a[1], b[1], cc[1]))); y1 = min(CELL - 1, int(max(a[1], b[1], cc[1])) + 1)
        den = (b[1] - cc[1]) * (a[0] - cc[0]) + (cc[0] - b[0]) * (a[1] - cc[1])
        if abs(den) < 1e-12:
            continue
        for py in range(y0, y1 + 1):
            fy = py + 0.5
            for px in range(x0, x1 + 1):
                fx = px + 0.5
                w0 = ((b[1] - cc[1]) * (fx - cc[0]) + (cc[0] - b[0]) * (fy - cc[1])) / den
                w1 = ((cc[1] - a[1]) * (fx - cc[0]) + (a[0] - cc[0]) * (fy - cc[1])) / den
                w2 = 1 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w0 * a[2] + w1 * b[2] + w2 * cc[2]
                i = py * CELL + px
                if z < zbuf[i]:
                    zbuf[i] = z
    def key(p):
        return (round(p[0] * 2000), round(p[1] * 2000), round(p[2] * 2000))
    def nrm(t):
        a, b, cc = t
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = cc[0] - a[0], cc[1] - a[1], cc[2] - a[2]
        n = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
        l = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1
        return (n[0] / l, n[1] / l, n[2] / l)
    norms = [nrm(t) for t in vt]
    edges = {}
    for ti, t in enumerate(vt):
        ks = [key(q) for q in t]
        for i in range(3):
            ka, kb = ks[i], ks[(i + 1) % 3]
            e = (ka, kb) if ka < kb else (kb, ka)
            edges.setdefault(e, [st[ti][i], st[ti][(i + 1) % 3], []])[2].append(ti)
    ang = math.cos(math.radians(40))
    lines = []
    for pu, pv, fs in edges.values():
        if len(fs) == 1:
            lines.append((pu, pv)); continue
        n0, n1 = norms[fs[0]], norms[fs[1]]
        dot = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2]
        if dot < ang or (n0[2] < 0) != (n1[2] < 0):
            lines.append((pu, pv))
    acc = [0.0] * (CELL * CELL)
    LW = 1.3
    for a, b in lines:
        L = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
        n = max(1, int(L * 2))
        for s in range(n + 1):
            t = s / n
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            z = a[2] + (b[2] - a[2]) * t
            ix, iy = int(x), int(y)
            if not (0 <= ix < CELL and 0 <= iy < CELL):
                continue
            zz = min(zbuf[iy * CELL + ix], zbuf[iy * CELL + min(CELL - 1, ix + 1)], zbuf[min(CELL - 1, iy + 1) * CELL + ix])
            if z > zz + 0.02:   # behind something (depth in metres)
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    d = math.hypot(ix + 0.5 + dx - x, iy + 0.5 + dy - y)
                    cov = max(0.0, min(1.0, LW / 2 + 0.5 - d))
                    j = (iy + dy) * CELL + ix + dx
                    if cov > 0 and 0 <= ix + dx < CELL and 0 <= iy + dy < CELL and cov > acc[j]:
                        acc[j] = cov
    for i in range(CELL * CELL):
        if zbuf[i] < INF and acc[i] < 0.12:
            acc[i] = 0.12
    return acc

def main():
    drones, mino, ref_json, raw = sys.argv[1:5]
    atlas = bytearray(AW * AH * 4)
    mappers = []
    for i, (name, folder, prefixes) in enumerate(UNITS):
        src = mino if folder is None else os.path.join(drones, folder)
        tris = []
        for f in sorted(os.listdir(src)):
            if f.endswith(".glb") and any(f.startswith(p) for p in prefixes):
                tris += read_glb(os.path.join(src, f))
        cell = render(tris)
        ox, oy = (i % 4) * CELL, (i // 4) * CELL
        for y in range(CELL):
            for x in range(CELL):
                v = int(cell[y * CELL + x] * 255)
                o = ((oy + y) * AW + ox + x) * 4
                atlas[o:o + 4] = bytes((v, v, v, v))
        single = bytearray(CELL * CELL * 4)
        for j, a in enumerate(cell):
            v = int(a * 255)
            single[j * 4:j * 4 + 4] = bytes((v, v, v, v))
        os.makedirs(os.path.join(raw, "preview"), exist_ok=True)
        png(os.path.join(raw, "preview", name + ".png"), CELL, CELL, single)
        mappers.append({
            "$type": "inkTextureAtlasMapper",
            "clippingRectInPixels": {"$type": "Rect", "bottom": 0, "left": 0, "right": 0, "top": 0},
            "clippingRectInUVCoords": {"$type": "RectF", "Bottom": (oy + CELL) / AH, "Left": ox / AW, "Right": (ox + CELL) / AW, "Top": oy / AH},
            "partName": {"$type": "CName", "$storage": "string", "$value": name},
        })
        print(name, len(tris), "triangles")
    os.makedirs(os.path.join(raw, os.path.dirname(DEPOT)), exist_ok=True)
    png(os.path.join(raw, DEPOT + ".png"), AW, AH, atlas)
    ref = json.load(open(ref_json, encoding="utf-8"))
    root = ref["Data"]["RootChunk"]
    tex = {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": DEPOT.replace("/", "\\") + ".xbm"}, "Flags": "Default"}
    for slot in root["slots"]["Elements"]:
        slot["parts"] = mappers
        slot["texture"] = json.loads(json.dumps(tex))
    root["textureResolution"] = "UltraHD_3840_2160"
    ref["Header"]["ArchiveFileName"] = DEPOT.replace("/", "\\") + ".inkatlas"
    json.dump(ref, open(os.path.join(raw, DEPOT + ".inkatlas.json"), "w", encoding="utf-8"), indent=2)


if __name__ == "__main__":
    main()
