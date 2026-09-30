# Packs the part layers into one atlas texture, and writes the inkatlas JSON (from the
# game's turret_hud.inkatlas as a template) and the layout the HUD script places them by.
import os, sys, json, zlib, struct

PARTS_DIR, REF_ATLAS_JSON, RAW_OUT, DEPOT = sys.argv[1:5]
AW, AH = 1024, 512


def read_png(path):
    data = open(path, 'rb').read()
    off = 8
    idat = b''
    while off < len(data):
        n, = struct.unpack('>I', data[off:off + 4]); t = data[off + 4:off + 8]; d = data[off + 8:off + 8 + n]
        if t == b'IHDR':
            w, h = struct.unpack('>II', d[:8])
        elif t == b'IDAT':
            idat += d
        off += 12 + n
    raw = zlib.decompress(idat)
    rows = []
    for y in range(h):
        line = raw[y * (w * 4 + 1):(y + 1) * (w * 4 + 1)]
        assert line[0] == 0
        rows.append(line[1:])
    return w, h, rows


def write_png(path, w, h, buf):
    raw = b''.join(b'\x00' + bytes(buf[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


lines = open(os.path.join(PARTS_DIR, 'layout.txt')).read().split('\n')
FW, FH = map(int, lines[0].split())
parts = [l.split() for l in lines[1:] if l.strip()]
# tallest first, shelf packing
order = sorted(parts, key=lambda p: -int(p[4]))
atlas = bytearray(AW * AH * 4)
x = y = shelf = 0
placed = {}
for name, ox, oy, w, h in order:
    w, h = int(w), int(h)
    if x + w + 2 > AW:
        x = 0; y += shelf + 2; shelf = 0
    assert y + h <= AH, 'atlas too small'
    pw, ph, rows = read_png(os.path.join(PARTS_DIR, name + '.png'))
    for r in range(ph):
        atlas[((y + r) * AW + x) * 4:((y + r) * AW + x + pw) * 4] = rows[r]
    placed[name] = (x, y, w, h, int(ox), int(oy))
    x += w + 2
    shelf = max(shelf, h)
os.makedirs(os.path.dirname(os.path.join(RAW_OUT, DEPOT + '.png')), exist_ok=True)
write_png(os.path.join(RAW_OUT, DEPOT + '.png'), AW, AH, atlas)

ref = json.load(open(REF_ATLAS_JSON, encoding='utf-8'))
root = ref['Data']['RootChunk']
mappers = []
for name in ['sensor', 'torso', 'arm_l', 'arm_r', 'leg_l', 'leg_r', 'pods']:
    px, py, w, h, ox, oy = placed[name]
    mappers.append({
        '$type': 'inkTextureAtlasMapper',
        'clippingRectInPixels': {'$type': 'Rect', 'bottom': 0, 'left': 0, 'right': 0, 'top': 0},
        'clippingRectInUVCoords': {'$type': 'RectF', 'Bottom': (py + h) / AH, 'Left': px / AW, 'Right': (px + w) / AW, 'Top': py / AH},
        'partName': {'$type': 'CName', '$storage': 'string', '$value': name},
    })
tex = {'DepotPath': {'$type': 'ResourcePath', '$storage': 'string', '$value': DEPOT.replace('/', '\\') + '.xbm'}, 'Flags': 'Default'}
for slot in root['slots']['Elements']:
    slot['parts'] = mappers
    slot['texture'] = json.loads(json.dumps(tex))
root['textureResolution'] = 'UltraHD_3840_2160'
ref['Header']['ArchiveFileName'] = DEPOT.replace('/', '\\') + '.inkatlas'
json.dump(ref, open(os.path.join(RAW_OUT, DEPOT + '.inkatlas.json'), 'w', encoding='utf-8'), indent=2)

with open(os.path.join(RAW_OUT, 'layout.reds.txt'), 'w') as fo:
    fo.write('// composite %d x %d\n' % (FW, FH))
    for name in ['sensor', 'torso', 'arm_l', 'arm_r', 'leg_l', 'leg_r', 'pods']:
        px, py, w, h, ox, oy = placed[name]
        fo.write('%s %d %d %d %d\n' % (name, ox, oy, w, h))
print(open(os.path.join(RAW_OUT, 'layout.reds.txt')).read())
