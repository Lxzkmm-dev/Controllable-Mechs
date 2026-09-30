# Front-view wireframe of the Minotaur, one layer per part (CMPart order).
# Pure standard library: glb parse, z-buffer, feature edges, PNG out.
import os, sys, math, zlib, struct
sys.path.insert(0, os.path.dirname(__file__))
from glb import meshes

SRC = sys.argv[1]
OUT = sys.argv[2]
MODE = sys.argv[3] if len(sys.argv) > 3 else 'preview'
SENSOR = eval(os.environ.get('SENSOR', '(-0.25, 0.25, 2.30, 9.0)'))  # xmin, xmax, ymin, ymax on the body

PARTS = ['sensor', 'torso', 'arm_l', 'arm_r', 'leg_l', 'leg_r', 'pods']
COLORS = [(255, 80, 80), (120, 255, 140), (80, 160, 255), (255, 200, 60), (200, 120, 255), (60, 230, 230), (255, 140, 200)]


def part_of(file, centroid):
    x, y, z = centroid
    if 'arm_l' in file or 'weapons_l' in file:
        return 2
    if 'arm_r' in file or 'weapons_r' in file:
        return 3
    if 'legs' in file:
        return 4 if x < 0 else 5
    if 'bags' in file:
        return 6
    if 'body' in file:
        if SENSOR[0] <= x <= SENSOR[1] and SENSOR[2] <= y <= SENSOR[3]:
            return 0
        return 1
    return 1  # hands and the rest: the torso


tris = []  # (p0, p1, p2, part)
for f in sorted(os.listdir(SRC)):
    if not f.endswith('.glb'):
        continue
    ms, js = meshes(os.path.join(SRC, f))
    for name, pos, tl, jo, we, jn in ms:
        if len(pos) < 300:
            continue  # decals, shadow and light cards
        for a, b, c in tl:
            pa, pb, pc = pos[a], pos[b], pos[c]
            cen = ((pa[0] + pb[0] + pc[0]) / 3, (pa[1] + pb[1] + pc[1]) / 3, (pa[2] + pb[2] + pc[2]) / 3)
            tris.append((pa, pb, pc, part_of(f, cen)))
print('triangles', len(tris))

xs = [p[0] for t in tris for p in t[:3]]
ys = [p[1] for t in tris for p in t[:3]]
xmin, xmax, ymin, ymax = min(xs), max(xs), min(ys), max(ys)
H = int(os.environ.get('H', '900'))
PAD = 8
k = (H - 2 * PAD) / (ymax - ymin)
W = int((xmax - xmin) * k) + 2 * PAD
print('size', W, H)


def proj(p):
    # front view, flipped so the mech's left is on the left; nearer = smaller z
    return ((p[0] - xmin) * k + PAD, (ymax - p[1]) * k + PAD, p[2])


INF = 1e9
zbuf = [INF] * (W * H)
owner = [-1] * (W * H)
podz = [INF] * (W * H)   # the pods sit behind the torso: drawn ghosted, from their own depth
for pa, pb, pc, part in tris:
    ghost = part == 6
    a, b, c = proj(pa), proj(pb), proj(pc)
    x0 = max(0, int(min(a[0], b[0], c[0]))); x1 = min(W - 1, int(max(a[0], b[0], c[0])) + 1)
    y0 = max(0, int(min(a[1], b[1], c[1]))); y1 = min(H - 1, int(max(a[1], b[1], c[1])) + 1)
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-12:
        continue
    for py in range(y0, y1 + 1):
        fy = py + 0.5
        for px in range(x0, x1 + 1):
            fx = px + 0.5
            w0 = ((b[1] - c[1]) * (fx - c[0]) + (c[0] - b[0]) * (fy - c[1])) / den
            w1 = ((c[1] - a[1]) * (fx - c[0]) + (a[0] - c[0]) * (fy - c[1])) / den
            w2 = 1 - w0 - w1
            if w0 < 0 or w1 < 0 or w2 < 0:
                continue
            z = w0 * a[2] + w1 * b[2] + w2 * c[2]
            i = py * W + px
            if ghost:
                if z < podz[i]:
                    podz[i] = z
                continue
            if z < zbuf[i]:
                zbuf[i] = z
                owner[i] = part

# feature edges: welded positions, dihedral angle, silhouettes, boundaries
def key(p):
    return (round(p[0] * 2000), round(p[1] * 2000), round(p[2] * 2000))


def normal(pa, pb, pc):
    ux, uy, uz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
    vx, vy, vz = pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2]
    n = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
    l = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1
    return (n[0] / l, n[1] / l, n[2] / l)


edges = {}
for ti, (pa, pb, pc, part) in enumerate(tris):
    ka, kb, kc = key(pa), key(pb), key(pc)
    for u, v, pu, pv in ((ka, kb, pa, pb), (kb, kc, pb, pc), (kc, ka, pc, pa)):
        e = (u, v) if u < v else (v, u)
        edges.setdefault(e, [pu, pv, []])[2].append(ti)
ANG = math.cos(math.radians(float(os.environ.get('ANG', '38'))))
norms = [normal(t[0], t[1], t[2]) for t in tris]
lines = []  # (pu, pv, part)
for e, (pu, pv, fs) in edges.items():
    part = tris[fs[0]][3]
    if len(fs) == 1:
        lines.append((pu, pv, part)); continue
    n0, n1 = norms[fs[0]], norms[fs[1]]
    dot = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2]
    sil = (n0[2] < 0) != (n1[2] < 0)
    if dot < ANG or sil:
        lines.append((pu, pv, part))
print('feature edges', len(lines))

LW = float(os.environ.get('LW', '1.6'))
EPS = 0.02
line = [[0.0] * (W * H) for _ in PARTS]


def plot(layer, x, y, a):
    if 0 <= x < W and 0 <= y < H:
        i = y * W + x
        if a > layer[i]:
            layer[i] = a


# the pods: their outline only
for py in range(H):
    for px in range(W):
        i = py * W + px
        if podz[i] < INF:
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                qx, qy = px + dx, py + dy
                if not (0 <= qx < W and 0 <= qy < H) or podz[qy * W + qx] >= INF:
                    edge = True
            if edge:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        plot(line[6], px + dx, py + dy, 1.0 if dx == 0 and dy == 0 else 0.5)

for pu, pv, part in lines:
    if part == 6:
        continue
    a, b = proj(pu), proj(pv)
    L = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
    n = max(1, int(L * 2))
    lay = line[part]
    for s in range(n + 1):
        t = s / n
        x = a[0] + (b[0] - a[0]) * t
        y = a[1] + (b[1] - a[1]) * t
        z = a[2] + (b[2] - a[2]) * t
        ix, iy = int(x), int(y)
        if not (0 <= ix < W and 0 <= iy < H):
            continue
        # visible: nothing in front of it (checked around the point, edges lie on surfaces)
        zz = min(zbuf[iy * W + ix], zbuf[iy * W + min(W - 1, ix + 1)], zbuf[min(H - 1, iy + 1) * W + ix])
        if z > zz + EPS:
            continue
        r = int(LW) + 1
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                d = math.hypot(ix + 0.5 + dx - x, iy + 0.5 + dy - y)
                cov = max(0.0, min(1.0, LW / 2 + 0.5 - d))
                if cov > 0:
                    plot(lay, ix + dx, iy + dy, cov)


def png(path, w, h, rgba):
    raw = b''.join(b'\x00' + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


os.makedirs(OUT, exist_ok=True)
FILL = float(os.environ.get('FILL', '0.16'))
if MODE == 'preview':
    buf = bytearray(W * H * 4)
    for i in range(W * H):
        o = owner[i]
        r = g = b = 12; a = 255
        if o < 0 and podz[i] < INF:
            o = 6
        if o >= 0:
            c = COLORS[o]
            r, g, b = int(c[0] * 0.25), int(c[1] * 0.25), int(c[2] * 0.25)
            for pi in range(len(PARTS)):
                l = line[pi][i]
                if l > 0:
                    c = COLORS[pi]
                    r = int(r + (c[0] - r) * l); g = int(g + (c[1] - g) * l); b = int(b + (c[2] - b) * l)
        buf[i * 4:i * 4 + 4] = bytes((r, g, b, a))
    png(os.path.join(OUT, 'preview.png'), W, H, buf)
else:
    # one white image per part, cropped to the part, with its offset in the whole
    meta = []
    for pi, pname in enumerate(PARTS):
        idx = [i for i in range(W * H) if owner[i] == pi or line[pi][i] > 0 or (pi == 6 and podz[i] < INF)]
        if not idx:
            continue
        xs_ = [i % W for i in idx]; ys_ = [i // W for i in idx]
        x0, x1, y0, y1 = max(0, min(xs_) - 2), min(W - 1, max(xs_) + 2), max(0, min(ys_) - 2), min(H - 1, max(ys_) + 2)
        w, h = x1 - x0 + 1, y1 - y0 + 1
        buf = bytearray(w * h * 4)
        for yy in range(h):
            for xx in range(w):
                i = (y0 + yy) * W + x0 + xx
                a = line[pi][i]
                if owner[i] == pi or (pi == 6 and podz[i] < INF):
                    a = max(a, FILL)
                buf[(yy * w + xx) * 4:(yy * w + xx) * 4 + 4] = bytes((255, 255, 255, int(a * 255)))
        png(os.path.join(OUT, pname + '.png'), w, h, buf)
        meta.append((pname, x0, y0, w, h))
    with open(os.path.join(OUT, 'layout.txt'), 'w') as fo:
        fo.write('%d %d\n' % (W, H))
        for m in meta:
            fo.write('%s %d %d %d %d\n' % m)
    print(open(os.path.join(OUT, 'layout.txt')).read())
