import json, struct, sys, os

CT = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def load(path):
    data = open(path, 'rb').read()
    magic, ver, length = struct.unpack_from('<III', data, 0)
    off = 12
    js = None
    binc = None
    while off < length:
        clen, ctype = struct.unpack_from('<II', data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        else:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor(js, binc, i):
    a = js['accessors'][i]
    bv = js['bufferViews'][a['bufferView']]
    n = NC[a['type']]
    fmt = CT[a['componentType']]
    size = struct.calcsize(fmt)
    stride = bv.get('byteStride', size * n)
    base = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    out = []
    for k in range(a['count']):
        v = struct.unpack_from('<' + fmt * n, binc, base + k * stride)
        out.append(v if n > 1 else v[0])
    return out


def meshes(path):
    """[(name, positions, triangles, joints, weights, jointNames)] for LOD 0 primitives"""
    js, binc = load(path)
    skins = js.get('skins', [])
    names = []
    if skins:
        names = [js['nodes'][j].get('name', str(j)) for j in skins[0]['joints']]
    res = []
    for m in js['meshes']:
        for p in m['primitives']:
            at = p['attributes']
            pos = accessor(js, binc, at['POSITION'])
            idx = accessor(js, binc, p['indices'])
            tris = [(idx[i], idx[i + 1], idx[i + 2]) for i in range(0, len(idx) - 2, 3)]
            jo = accessor(js, binc, at['JOINTS_0']) if 'JOINTS_0' in at else None
            we = accessor(js, binc, at['WEIGHTS_0']) if 'WEIGHTS_0' in at else None
            res.append((m.get('name', ''), pos, tris, jo, we, names))
    return res, js


if __name__ == '__main__':
    d = sys.argv[1]
    for f in sorted(os.listdir(d)):
        if not f.endswith('.glb'):
            continue
        ms, js = meshes(os.path.join(d, f))
        print(f, 'meshes', len(js['meshes']), 'nodes', len(js['nodes']), 'skins', len(js.get('skins', [])))
        for name, pos, tris, jo, we, jn in ms:
            xs = [p[0] for p in pos]; ys = [p[1] for p in pos]; zs = [p[2] for p in pos]
            print('  ', name, len(pos), 'v', len(tris), 't', 'x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f' % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)), 'skin' if jo else '')
