# The drones' HUD damage schematics: a top-down wireframe of each drone, one white layer
# per part (hidden lines removed, feature edges only, a faint fill), packed into one atlas
# with an inkatlas naming the parts, and the layout (each part's place in the whole) the
# HUD script places them by.
#
# Usage: python schematic.py <folder with raw_<kind>/*.glb> <turret_hud.inkatlas.json> <raw out folder>
# Standard library only. glTF is Y-up: game (X, Y, Z) = glTF (x, -z, y); top-down shows X
# across and Y (forward) up.
import json, math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from scan import read_glb, accessor, png  # noqa: E402
import struct  # noqa: E402


def read_glb_skinned(path):
    # read_glb's triangles, each with the mesh it is in and the bones its corners follow
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    blen = struct.unpack("<I", b[off:off + 4])[0]
    binc = b[off + 8:off + 8 + blen]
    joints = j["skins"][0]["joints"] if j.get("skins") else []
    out = []
    for m in j["meshes"]:
        if "LOD_1" not in m.get("name", "LOD_1"):
            continue
        for pr in m["primitives"]:
            pos = accessor(j, binc, pr["attributes"]["POSITION"])
            idx = accessor(j, binc, pr["indices"]) if "indices" in pr else list(range(len(pos)))
            jw = accessor(j, binc, pr["attributes"]["JOINTS_0"]) if "JOINTS_0" in pr["attributes"] and joints else None
            pts = [(q[0], -q[2], q[1]) for q in pos]
            for i in range(0, len(idx) - 2, 3):
                c = (idx[i], idx[i + 1], idx[i + 2])
                bones = [j["nodes"][joints[jw[k][0]]]["name"] for k in c] if jw else []
                out.append(((pts[c[0]], pts[c[1]], pts[c[2]]), m.get("name", ""), bones))
    return out

AW, AH = 1024, 1024
H = 560          # the composite's height in pixels
LW = 2.0
FILL = 0.14


def octant_part(mesh, c, sub="", bones=()):
    # the four thruster pods are their own meshes, hung on Slot8842 slots (below); the front
    # gun is its own mesh. In the body mesh (0.7.1-a34, Omar: wireframe scans of the game's
    # asset only): the five tubes down each side follow the l/r_element bones (the rocket
    # pods); the sensor is the nose lens (submesh_03) and the nose round it; the mortar is
    # the right half of the rear block (Omar's pick; the Octant has no mortar of its own: a
    # region of the body's own lines). Everything else is the body.
    if mesh.startswith("av_zetatech_octant__ext01_gun"):
        return "gun"
    for side in ("fl", "fr", "bl", "br"):
        if mesh.startswith("av_zetatech_octant__ext01_thruster_" + side):
            return "thruster_" + side
    if any(b.startswith("l_element") for b in bones):
        return "rocket_l"
    if any(b.startswith("r_element") for b in bones):
        return "rocket_r"
    if sub.startswith("submesh_03") or (c[1] > 1.2 and abs(c[0]) < 0.3 and c[2] > -0.15):
        return "sensor"
    if -1.62 < c[1] < -0.6 and 0.02 < c[0] < 0.47 and c[2] > -0.1:
        return "mortar"
    return "body"


# rigid meshes in their slot's frame: where each slot sits in the rest pose (rig bones
# composed with Slot8842's slot offsets, all unturned): av_zetatech_octant.rig / .ent
PLACED = {
    "av_zetatech_octant__ext01_thruster_fl": (-0.877, 0.588, 0.607),
    "av_zetatech_octant__ext01_thruster_fr": (0.877, 0.588, 0.607),
    "av_zetatech_octant__ext01_thruster_bl": (-0.88, -0.567, 0.722),
    "av_zetatech_octant__ext01_thruster_br": (0.88, -0.567, 0.722),
}


DRONES = {
    "octant": ("raw_octant", ["av_zetatech_octant__ext01_body_01", "av_zetatech_octant__ext01_gun_02", "av_zetatech_octant__ext01_thruster_"],
               octant_part, ["body", "thruster_fl", "thruster_fr", "thruster_bl", "thruster_br", "gun", "rocket_l", "rocket_r", "mortar", "sensor"]),
}


def render(tris, parts):
    # tris: (p0, p1, p2, part index); top-down: screen x = X, screen y = -Y, depth = -Z
    xs = [p[0] for t in tris for p in t[:3]]
    ys = [p[1] for t in tris for p in t[:3]]
    k = (H - 16) / (max(ys) - min(ys))
    W = int((max(xs) - min(xs)) * k) + 16
    x0, y1 = min(xs), max(ys)
    def proj(p):
        return ((p[0] - x0) * k + 8, (y1 - p[1]) * k + 8, -p[2])
    INF = 1e9
    zbuf = [INF] * (W * H)
    owner = [-1] * (W * H)
    for t in tris:
        a, b, c = proj(t[0]), proj(t[1]), proj(t[2])
        xa = max(0, int(min(a[0], b[0], c[0]))); xb = min(W - 1, int(max(a[0], b[0], c[0])) + 1)
        ya = max(0, int(min(a[1], b[1], c[1]))); yb = min(H - 1, int(max(a[1], b[1], c[1])) + 1)
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        for py in range(ya, yb + 1):
            fy = py + 0.5
            for px in range(xa, xb + 1):
                fx = px + 0.5
                w0 = ((b[1] - c[1]) * (fx - c[0]) + (c[0] - b[0]) * (fy - c[1])) / den
                w1 = ((c[1] - a[1]) * (fx - c[0]) + (a[0] - c[0]) * (fy - c[1])) / den
                w2 = 1 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w0 * a[2] + w1 * b[2] + w2 * c[2]
                i = py * W + px
                if z < zbuf[i]:
                    zbuf[i] = z
                    owner[i] = t[3]
    def key(p):
        return (round(p[0] * 2000), round(p[1] * 2000), round(p[2] * 2000))
    def nrm(t):
        a, b, c = t[0], t[1], t[2]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2]); v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        l = math.sqrt(sum(q * q for q in n)) or 1
        return (n[0] / l, n[1] / l, n[2] / l)
    norms = [nrm(t) for t in tris]
    edges = {}
    for ti, t in enumerate(tris):
        for i in range(3):
            pa, pb = t[i], t[(i + 1) % 3]
            ka, kb = key(pa), key(pb)
            e = (ka, kb) if ka < kb else (kb, ka)
            edges.setdefault(e, [pa, pb, []])[2].append(ti)
    ang = math.cos(math.radians(40))
    line = [[0.0] * (W * H) for _ in parts]
    for pa, pb, fs in edges.values():
        part = tris[fs[0]][3]
        if len(fs) > 1:
            n0, n1 = norms[fs[0]], norms[fs[1]]
            dot = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2]
            if not (dot < ang or (n0[2] < 0) != (n1[2] < 0)):
                continue
        a, b = proj(pa), proj(pb)
        L = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
        n = max(1, int(L * 2))
        lay = line[part]
        for s in range(n + 1):
            t = s / n
            x = a[0] + (b[0] - a[0]) * t; y = a[1] + (b[1] - a[1]) * t; z = a[2] + (b[2] - a[2]) * t
            ix, iy = int(x), int(y)
            if not (0 <= ix < W and 0 <= iy < H):
                continue
            zz = min(zbuf[iy * W + ix], zbuf[iy * W + min(W - 1, ix + 1)], zbuf[min(H - 1, iy + 1) * W + ix])
            if z > zz + 0.03:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    d = math.hypot(ix + 0.5 + dx - x, iy + 0.5 + dy - y)
                    cov = max(0.0, min(1.0, LW / 2 + 0.5 - d))
                    j = (iy + dy) * W + ix + dx
                    if cov > 0 and 0 <= ix + dx < W and 0 <= iy + dy < H and cov > lay[j]:
                        lay[j] = cov
    return W, owner, line


def main():
    src, ref_json, raw = sys.argv[1:4]
    os.makedirs(raw, exist_ok=True)
    layout = {}
    images = []
    for kind, (folder, prefixes, part_of, parts) in DRONES.items():
        tris = []
        for f in sorted(os.listdir(os.path.join(src, folder))):
            if f.endswith(".glb") and any(f.startswith(p) for p in prefixes):
                off = next((o for p, o in PLACED.items() if f.startswith(p)), (0.0, 0.0, 0.0))
                for t, sub, bones in read_glb_skinned(os.path.join(src, folder, f)):
                    t = tuple(tuple(q[i] + off[i] for i in range(3)) for q in t)
                    c = tuple((t[0][i] + t[1][i] + t[2][i]) / 3 for i in range(3))
                    tris.append((t[0], t[1], t[2], parts.index(part_of(f, c, sub, bones))))
        W, owner, line = render(tris, parts)
        comp = bytearray(W * H * 4)
        for pi, pname in enumerate(parts):
            idx = [i for i in range(W * H) if owner[i] == pi or line[pi][i] > 0]
            if not idx:
                continue
            xs = [i % W for i in idx]; ys = [i // W for i in idx]
            x0, x1, y0, y1 = max(0, min(xs) - 2), min(W - 1, max(xs) + 2), max(0, min(ys) - 2), min(H - 1, max(ys) + 2)
            w, h = x1 - x0 + 1, y1 - y0 + 1
            buf = bytearray(w * h * 4)
            for yy in range(h):
                for xx in range(w):
                    i = (y0 + yy) * W + x0 + xx
                    a = line[pi][i]
                    if owner[i] == pi:
                        a = max(a, FILL)
                    v = int(a * 255)
                    buf[(yy * w + xx) * 4:(yy * w + xx) * 4 + 4] = bytes((v, v, v, v))
                    if v > comp[i * 4]:
                        comp[i * 4:i * 4 + 4] = bytes((v, v, v, v))
            images.append((kind + "_" + pname, w, h, buf))
            layout[kind + "_" + pname] = [x0, y0, w, h]
        layout[kind] = [0, 0, W, H]
        png(os.path.join(raw, kind + "_preview.png"), W, H, comp)
    # shelf-pack the part layers, tallest first
    atlas = bytearray(AW * AH * 4)
    placed = {}
    x = y = shelf = 0
    for name, w, h, buf in sorted(images, key=lambda t: -t[2]):
        if x + w + 2 > AW:
            x = 0; y += shelf + 2; shelf = 0
        assert y + h <= AH, "atlas too small"
        for r in range(h):
            o = ((y + r) * AW + x) * 4
            atlas[o:o + w * 4] = buf[r * w * 4:(r + 1) * w * 4]
        placed[name] = (x, y, w, h)
        x += w + 2
        shelf = max(shelf, h)
    depot = "mnc/hud/drone_schematics"
    os.makedirs(os.path.join(raw, os.path.dirname(depot)), exist_ok=True)
    png(os.path.join(raw, depot + ".png"), AW, AH, atlas)
    ref = json.load(open(ref_json, encoding="utf-8"))
    root = ref["Data"]["RootChunk"]
    mappers = []
    for name, (px, py, w, h) in placed.items():
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
    json.dump(ref, open(os.path.join(raw, depot + ".inkatlas.json"), "w", encoding="utf-8"), indent=2)
    json.dump(layout, open(os.path.join(raw, "layout.json"), "w"), indent=1)
    print(json.dumps(layout))


if __name__ == "__main__":
    main()
