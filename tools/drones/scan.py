# Wireframe scan of the drones' real meshes (glTF exported by WolvenKit).
#
# For each drone type it writes:
#   - the contact hull: the mesh's support points along 26 directions (cube faces, edges
#     and corners), relative to the entity origin in the game frame (X right, Y forward,
#     Z up), deduplicated; the flight model's collision touches the world at these
#   - the sight-view sensor mount default: at the nose, at the centre-of-mass height
#   - wireframes, top-down (the quads' schematic view) and side, as white-on-transparent
#     PNGs with premultiplied alpha (the HUD texture convention), for the damage sprite
# and generates r6/scripts/ControllableMechs/Control/CMDroneHull.reds from the hulls.
#
# Usage: python scan.py <folder with raw_<kind>/*.glb> <mod root>
# Standard library only. glTF is Y-up: game (X, Y, Z) = glTF (x, -z, y).
import json, math, os, struct, sys, zlib

KINDS = {
    # kind: (folder, mesh files to use (prefix match), centre-of-mass height above origin)
    "bombus": ("raw_bombus", ["av_zetatech_bombus__ext01_surveillance", "av_zetatech_bombus__ext01_propellers", "av_zetatech_bombus__weapon"], 0.13),
    "griffin": ("raw_griffin", ["av_militech_griffin_body_01", "av_militech_griffin_wing_l_01", "av_militech_griffin_wing_r_01"], 0.0),
    "wyvern": ("raw_wyvern", ["av_militech_wyvern_01"], 0.22),
    # the thruster meshes are in their own attachment frames: body and front gun only
    "octant": ("raw_octant", ["av_zetatech_octant__ext01_body_01", "av_zetatech_octant__ext01_gun_02"], 0.15),
}


def read_glb(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    blen = struct.unpack("<I", b[off:off + 4])[0]
    binc = b[off + 8:off + 8 + blen]
    tris = []
    for m in j["meshes"]:
        if "LOD_1" not in m.get("name", "LOD_1"):
            continue
        for pr in m["primitives"]:
            pos = accessor(j, binc, pr["attributes"]["POSITION"])
            idx = accessor(j, binc, pr["indices"]) if "indices" in pr else list(range(len(pos)))
            pts = [(p[0], -p[2], p[1]) for p in pos]
            for i in range(0, len(idx) - 2, 3):
                tris.append((pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]))
    return tris


def accessor(j, binc, ai):
    a = j["accessors"][ai]
    v = j["bufferViews"][a["bufferView"]]
    comp = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}[a["componentType"]]
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", comp[1] * ncomp)
    out = []
    for i in range(a["count"]):
        o = start + i * stride
        vals = struct.unpack("<" + comp[0] * ncomp, binc[o:o + comp[1] * ncomp])
        out.append(vals if ncomp > 1 else vals[0])
    return out


def hull(points):
    dirs = []
    for x in (-1, 0, 1):
        for y in (-1, 0, 1):
            for z in (-1, 0, 1):
                if x or y or z:
                    l = math.sqrt(x * x + y * y + z * z)
                    dirs.append((x / l, y / l, z / l))
    sup = []
    for d in dirs:
        best = max(points, key=lambda p: p[0] * d[0] + p[1] * d[1] + p[2] * d[2])
        if all(math.dist(best, s) > 0.04 for s in sup):
            sup.append(best)
    # at most 12 (each is a ray every frame): farthest-point sampling keeps them spread,
    # starting from the lowest (the one that touches down first)
    sel = [min(sup, key=lambda p: p[2])]
    while len(sel) < min(12, len(sup)):
        sel.append(max((p for p in sup if p not in sel), key=lambda p: min(math.dist(p, s) for s in sel)))
    return sel


def png(path, w, h, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def wireframe(tris, axes, size, path):
    # axes: which game axes go across and up the picture, e.g. (0, 1) top-down
    a, b = axes
    xs = [p[a] for t in tris for p in t]
    ys = [p[b] for t in tris for p in t]
    lo_x, hi_x, lo_y, hi_y = min(xs), max(xs), min(ys), max(ys)
    span = max(hi_x - lo_x, hi_y - lo_y) * 1.08
    cx, cy = (lo_x + hi_x) / 2, (lo_y + hi_y) / 2
    acc = [0.0] * (size * size)
    def px(p):
        return ((p[a] - cx) / span + 0.5) * (size - 1), (0.5 - (p[b] - cy) / span) * (size - 1)
    edges = set()
    for t in tris:
        for i in range(3):
            e = (t[i], t[(i + 1) % 3])
            edges.add(e if e[0] <= e[1] else (e[1], e[0]))
    for p, q in edges:
        x0, y0 = px(p)
        x1, y1 = px(q)
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for k in range(n + 1):
            x = int(round(x0 + (x1 - x0) * k / n))
            y = int(round(y0 + (y1 - y0) * k / n))
            if 0 <= x < size and 0 <= y < size:
                acc[y * size + x] += 0.18
    rgba = bytearray(size * size * 4)
    for i, v in enumerate(acc):
        al = min(1.0, v)
        c = int(al * 255)   # white, premultiplied
        rgba[i * 4:i * 4 + 4] = bytes((c, c, c, c))
    png(path, size, size, rgba)


def main():
    src, root = sys.argv[1], sys.argv[2]
    docs = os.path.join(root, "docs", "drones")
    os.makedirs(docs, exist_ok=True)
    out = {}
    for kind, (folder, prefixes, com) in KINDS.items():
        tris = []
        for f in sorted(os.listdir(os.path.join(src, folder))):
            if f.endswith(".glb") and any(f.startswith(p) for p in prefixes):
                tris += read_glb(os.path.join(src, folder, f))
        pts = list({p for t in tris for p in t})
        h = hull(pts)
        nose = max(p[1] for p in pts)
        out[kind] = {
            "com": com,
            "bounds": [[min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]],
            "hull": [[round(c, 3) for c in p] for p in h],
            "sensor": {"up": round(com, 2), "fwd": round(nose + 0.05, 2)},
        }
        wireframe(tris, (0, 1), 512, os.path.join(docs, kind + "_top.png"))
        wireframe(tris, (1, 2), 512, os.path.join(docs, kind + "_side.png"))
        print(kind, len(tris), "triangles,", len(h), "hull points, bounds", out[kind]["bounds"])
    json.dump(out, open(os.path.join(docs, "hulls.json"), "w"), indent=1)
    write_reds(out, os.path.join(root, "r6", "scripts", "ControllableMechs", "Control", "CMDroneHull.reds"))


def write_reds(out, path):
    L = ["// =============================================================================",
         "// MECHS OF NIGHT CITY - DRONE CONTACT HULLS (generated by tools/drones/scan.py)",
         "//",
         "// Each drone's contact points, scanned from its real meshes: the support points along",
         "// 26 directions, in metres from the entity origin (X right, Y forward, Z up), and the",
         "// sight-view sensor mount default (at the nose, centre-of-mass height). Don't edit by",
         "// hand: re-run the scan.",
         "// =============================================================================",
         "module ControllableMechs.Control",
         "",
         "public abstract class CMDroneHull {",
         "  public static func Points(kind: String) -> array<Vector4> {",
         "    switch kind {"]
    for kind, d in out.items():
        L.append('      case "%s":' % kind)
        pts = ", ".join("new Vector4(%.3f, %.3f, %.3f, 0.0)" % tuple(p) for p in d["hull"])
        L.append("        return [%s];" % pts)
    L += ["    }", "    let none: array<Vector4>;", "    return none;", "  }", "",
          "  // sensor mount defaults (cm): height above the origin, forward of it",
          "  public static func SensorUpCm(kind: String) -> Int32 {", "    switch kind {"]
    for kind, d in out.items():
        L.append('      case "%s": return %d;' % (kind, round(d["sensor"]["up"] * 100)))
    L += ["    }", "    return 10;", "  }", "",
          "  public static func SensorFwdCm(kind: String) -> Int32 {", "    switch kind {"]
    for kind, d in out.items():
        L.append('      case "%s": return %d;' % (kind, round(d["sensor"]["fwd"] * 100)))
    L += ["    }", "    return 35;", "  }", "}", ""]
    open(path, "w", newline="\n", encoding="utf-8").write("\n".join(L))


if __name__ == "__main__":
    main()
