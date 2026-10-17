"""Мини-библиотека для чтения/записи glTF (json + bin) через numpy. Без внешних зависимостей."""
import json, os, struct, copy
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

class Gltf:
    def __init__(self, path):
        self.path = path; self.dir = os.path.dirname(path)
        if path.endswith('.glb'):
            b = open(path, 'rb').read()
            l = struct.unpack('<I', b[12:16])[0]
            self.j = json.loads(b[20:20 + l])
            o = 20 + l
            bl = struct.unpack('<I', b[o:o + 4])[0]
            self.bins = [b[o + 8:o + 8 + bl]]
        else:
            self.j = json.load(open(path))
            self.bins = [open(os.path.join(self.dir, buf['uri']), 'rb').read() for buf in self.j['buffers']]

    def acc(self, i):
        a = self.j['accessors'][i]; bv = self.j['bufferViews'][a['bufferView']]
        dt = CT[a['componentType']]; n = NC[a['type']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride', 0)
        isz = np.dtype(dt).itemsize * n
        buf = self.bins[bv['buffer']]
        if stride and stride != isz:
            raw = np.frombuffer(buf, dtype=np.uint8, count=stride * (a['count'] - 1) + isz, offset=off)
            idx = np.arange(a['count'])[:, None] * stride + np.arange(isz)[None, :]
            arr = raw[idx].view(dt).reshape(a['count'], n)
        else:
            arr = np.frombuffer(buf, dtype=dt, count=a['count'] * n, offset=off).reshape(a['count'], n)
        if a.get('normalized') and dt != np.float32:
            arr = arr.astype(np.float32) / np.iinfo(dt).max
        return arr.copy() if n > 1 else arr.reshape(-1).copy()

    def node_by_name(self, name):
        for i, n in enumerate(self.j['nodes']):
            if n.get('name') == name: return i
        return -1

class Writer:
    """Собирает новый glTF: добавляет массивы в общий bin."""
    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "oskolki-asset-pipeline"}, "scene": 0,
                  "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "skins": [], "accessors": [],
                  "bufferViews": [], "buffers": [], "materials": [], "textures": [], "images": [], "samplers": []}
        self.bin = bytearray()

    def add(self, arr, target=None, minmax=False, typ=None):
        arr = np.ascontiguousarray(arr)
        dt = arr.dtype
        ct = {np.dtype(np.float32): 5126, np.dtype(np.uint16): 5123, np.dtype(np.uint32): 5125, np.dtype(np.uint8): 5121}[dt]
        n = 1 if arr.ndim == 1 else arr.shape[1]
        if typ is None: typ = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4", 16: "MAT4"}[n]
        while len(self.bin) % 4: self.bin.append(0)
        bv = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": arr.nbytes}
        if target: bv["target"] = target
        self.bin += arr.tobytes()
        self.j['bufferViews'].append(bv)
        a = {"bufferView": len(self.j['bufferViews']) - 1, "componentType": ct, "count": arr.shape[0], "type": typ}
        if minmax:
            a["min"] = [float(x) for x in np.atleast_1d(arr.min(axis=0))]; a["max"] = [float(x) for x in np.atleast_1d(arr.max(axis=0))]
        self.j['accessors'].append(a)
        return len(self.j['accessors']) - 1

    def add_image(self, uri):
        self.j['images'].append({"uri": uri})
        if not self.j['samplers']: self.j['samplers'].append({"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497})
        self.j['textures'].append({"sampler": 0, "source": len(self.j['images']) - 1})
        return len(self.j['textures']) - 1

    def save(self, path):
        base = os.path.splitext(os.path.basename(path))[0]
        self.j['buffers'] = [{"uri": base + ".bin", "byteLength": len(self.bin)}]
        for k in list(self.j.keys()):
            if isinstance(self.j[k], list) and not self.j[k]: del self.j[k]
        json.dump(self.j, open(path, 'w'), separators=(',', ':'))
        open(os.path.join(os.path.dirname(path), base + ".bin"), 'wb').write(self.bin)
