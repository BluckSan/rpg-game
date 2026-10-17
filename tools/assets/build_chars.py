"""Сборка персонажей из CC0-ассетов Quaternius (Universal Base Characters + Modular Character Outfits Fantasy).
Результат: assets/characters/human_{m,f}.gltf — один скелет, все части (голова, тело, глаза, брови, причёски,
борода, наряды Ranger/Peasant), у головы и причёсок — сгенерированные морфы (blend shapes) для редактора лица.
Текстуры перепаковываются в атласы (только нужные UV-острова) и уменьшаются под мобильные устройства.
Запуск: python3 tools/assets/build_chars.py  (исходники в ~/assets_dl, см. README)"""
import os, sys, json, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from gltfio import Gltf, Writer

HOME = os.path.expanduser('~/assets_dl')
UBC = HOME + '/ubc/Universal Base Characters[Standard]/'
BASE = UBC + 'Base Characters/Godot - UE/'
BTEX = UBC + 'Base Characters/Textures/'
HAIR = UBC + 'Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/'
HTEX = UBC + 'Hairstyles/Textures/'
MC = HOME + '/mcof/Modular Character Outfits - Fantasy[Standard]/'
OUTF = MC + 'Exports/glTF (Godot-Unreal)/Outfits/'
MTEX = MC + 'Textures/'
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'characters')
TEXOUT = os.path.join(OUT, 'tex')
os.makedirs(TEXOUT, exist_ok=True)

# ---------------------------------------------------------------- примитивы
def prims_of(g, mesh_idx):
    out = []
    for p in g.j['meshes'][mesh_idx]['primitives']:
        a = p['attributes']
        d = dict(pos=g.acc(a['POSITION']).astype(np.float32), nrm=g.acc(a['NORMAL']).astype(np.float32),
                 uv=g.acc(a['TEXCOORD_0']).astype(np.float32), joints=g.acc(a['JOINTS_0']).astype(np.uint16),
                 weights=g.acc(a['WEIGHTS_0']).astype(np.float32), idx=g.acc(p['indices']).astype(np.uint32).reshape(-1, 3),
                 mat=g.j['materials'][p['material']]['name'] if 'material' in p else '')
        out.append(d)
    return out

def subset(pr, tri_mask):
    tris = pr['idx'][tri_mask]
    used = np.unique(tris)
    remap = -np.ones(len(pr['pos']), np.int64); remap[used] = np.arange(len(used))
    d = {k: (v[used] if isinstance(v, np.ndarray) and v.ndim >= 1 and len(v) == len(pr['pos']) else v) for k, v in pr.items()}
    d['idx'] = remap[tris].astype(np.uint32)
    return d

def skin_info(g):
    s = g.j['skins'][0]
    names = [g.j['nodes'][i]['name'] for i in s['joints']]
    ibm = g.acc(s['inverseBindMatrices']).astype(np.float32).reshape(-1, 16)
    return names, ibm

# ---------------------------------------------------------------- атласы
def islands(prs):
    """UV-острова: компоненты связности по индексам вершин. Возвращает список (prim_i, vert_ids, bbox)."""
    res = []
    for pi, pr in enumerate(prs):
        n = len(pr['pos']); parent = np.arange(n)
        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]; a = parent[a]
            return a
        for t in pr['idx']:
            ra, rb, rc = find(t[0]), find(t[1]), find(t[2])
            parent[rb] = ra; parent[find(rc)] = ra
        roots = np.array([find(i) for i in range(n)])
        usedv = np.unique(pr['idx'])
        for r in np.unique(roots[usedv]):
            vs = usedv[roots[usedv] == r]
            uv = pr['uv'][vs]
            res.append((pi, vs, uv.min(0), uv.max(0)))
    return res

def pack(prs, srcs, out_name, size, scale, pad=6, keep_full=False):
    """Перепаковывает UV-острова из исходных текстур srcs {канал: путь} в атлас size×size с масштабом scale.
    Если keep_full — просто уменьшает текстуру целиком."""
    ims = {k: Image.open(v) for k, v in srcs.items() if v}
    W, H = next(iter(ims.values())).size
    out = {}
    if keep_full:
        for k, im in ims.items():
            s = size if k == 'albedo' else max(256, size // 2)
            out[k] = im.convert('RGBA' if im.mode == 'RGBA' else 'RGB').resize((s, s), Image.LANCZOS)
    else:
        isl = islands(prs)
        # объединяем пересекающиеся прямоугольники, чтобы не дублировать пиксели
        rects = []
        for pi, vs, mn, mx in isl:
            x0, y0 = int(math.floor(mn[0] * W)) - pad, int(math.floor(mn[1] * H)) - pad
            x1, y1 = int(math.ceil(mx[0] * W)) + pad, int(math.ceil(mx[1] * H)) + pad
            rects.append([max(0, x0), max(0, y0), min(W, x1), min(H, y1), [(pi, vs)]])
        merged = True
        while merged:
            merged = False
            for a in range(len(rects)):
                for b in range(a + 1, len(rects)):
                    A, B = rects[a], rects[b]
                    if A[0] < B[2] and B[0] < A[2] and A[1] < B[3] and B[1] < A[3]:
                        rects[a] = [min(A[0], B[0]), min(A[1], B[1]), max(A[2], B[2]), max(A[3], B[3]), A[4] + B[4]]
                        del rects[b]; merged = True; break
                if merged: break
        # полочная упаковка
        while True:
            order = sorted(range(len(rects)), key=lambda i: -(rects[i][3] - rects[i][1]))
            x = y = shelf = 0; place = {}; ok = True
            for i in order:
                w = int((rects[i][2] - rects[i][0]) * scale) + 1; h = int((rects[i][3] - rects[i][1]) * scale) + 1
                if x + w > size: x = 0; y += shelf; shelf = 0
                if y + h > size or w > size: ok = False; break
                place[i] = (x, y, w, h); x += w; shelf = max(shelf, h)
            if ok: break
            scale *= 0.92
        print('   atlas', out_name, 'scale %.2f' % scale, 'rects', len(rects))
        for k, im in ims.items():
            mode = 'RGBA' if im.mode == 'RGBA' else ('L' if im.mode == 'L' else 'RGB')
            s = size if k == 'albedo' else max(256, size // 2)
            f = s / size
            fill = {'normal': (128, 128, 255), 'rough': 160, 'orm': (255, 160, 0)}.get(k, (128, 110, 100))
            if mode == 'RGBA' and isinstance(fill, tuple) and len(fill) == 3: fill = fill + (255,)
            if mode == 'L' and isinstance(fill, tuple): fill = 160
            atlas = Image.new(mode, (s, s), fill)
            src = im.convert(mode)
            for i, (px, py, w, h) in place.items():
                r = rects[i]
                crop = src.crop((r[0], r[1], r[2], r[3])).resize((max(1, int(w * f)), max(1, int(h * f))), Image.LANCZOS)
                atlas.paste(crop, (int(px * f), int(py * f)))
            out[k] = atlas
        # UV remap
        for i, (px, py, w, h) in place.items():
            r = rects[i]
            for pi, vs in r[4]:
                uv = prs[pi]['uv']
                u = (uv[vs, 0] * W - r[0]) * scale + px
                v = (uv[vs, 1] * H - r[1]) * scale + py
                uv[vs, 0] = u / size; uv[vs, 1] = v / size
    paths = {}
    for k, im in out.items():
        p = os.path.join(TEXOUT, f'{out_name}_{k}.png')
        im.save(p, optimize=True); paths[k] = 'tex/' + os.path.basename(p)
    return paths

# ---------------------------------------------------------------- морфы лица
def landmarks(g):
    j = g.j
    meshes = {n['name']: n['mesh'] for n in j['nodes'] if 'mesh' in n}
    eyes = g.acc(j['meshes'][meshes['Eyes']]['primitives'][0]['attributes']['POSITION'])
    eL = eyes[eyes[:, 0] > 0].mean(0); eR = eyes[eyes[:, 0] < 0].mean(0)
    E = (eL + eR) / 2; d = float(np.linalg.norm(eL - eR))
    return dict(E=E, d=d, eye=np.array([abs(eL[0] - E[0]) / d, 0, 0]))

def sstep(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def gauss(q, c, r):
    """Симметричная по X гауссиана: c задаётся для правой стороны (x>0), зеркалится."""
    dq = q.copy(); dq[:, 0] = np.abs(dq[:, 0])
    rr = np.asarray(r, np.float32)
    return np.exp(-(((dq - c) / rr) ** 2).sum(1) / 2)

FACE_MORPHS = ['face_width', 'face_length', 'jaw_width', 'chin', 'cheekbones', 'cheeks', 'eye_size', 'eye_spacing',
               'eye_height', 'nose_length', 'nose_width', 'nose_bridge', 'lips', 'mouth_width', 'brow_height',
               'brow_depth', 'ears_size', 'ears_point']
EXTRA_MORPHS = ['beard_length', 'beard_volume', 'hair_volume']

def field(name, q):
    """Смещение (в единицах межзрачкового расстояния d) для нормированных координат q=(p-E)/d."""
    x, y, z = q[:, 0], q[:, 1], q[:, 2]
    sg = np.sign(x)
    D = np.zeros_like(q)
    neck = sstep(y, -2.9, -2.0)          # шея не двигается
    front = sstep(z, -1.6, -0.4)
    if name == 'face_width':
        D[:, 0] = x * 0.13 * front * neck * (1 - sstep(y, 0.5, 1.6))
    elif name == 'face_length':
        D[:, 1] = np.minimum(y + 0.6, 0) * 0.16 * front * neck
    elif name == 'jaw_width':
        g = gauss(q, [0.95, -1.35, -0.75], [0.5, 0.6, 0.6]); D[:, 0] = sg * 0.24 * g
    elif name == 'chin':
        g = gauss(q, [0.0, -1.7, 0.1], [0.45, 0.4, 0.5]); D[:, 1] = -0.17 * g; D[:, 2] = 0.1 * g
    elif name == 'cheekbones':
        g = gauss(q, [0.85, -0.35, -0.2], [0.35, 0.3, 0.4]); D[:, 0] = sg * 0.12 * g; D[:, 2] = 0.05 * g; D[:, 1] = 0.03 * g
    elif name == 'cheeks':
        g = gauss(q, [0.65, -0.95, 0.0], [0.35, 0.35, 0.35]); D[:, 0] = sg * 0.11 * g; D[:, 2] = 0.06 * g
    elif name == 'eye_size':
        c = np.array([0.5, 0.0, 0.0]); g = gauss(q, c, [0.33, 0.28, 0.4])
        rel = q.copy(); rel[:, 0] = np.abs(rel[:, 0]) - 0.5
        D = rel * 0.28 * g[:, None]; D[:, 0] *= sg
    elif name == 'eye_spacing':
        g = gauss(q, [0.5, 0.0, 0.0], [0.42, 0.35, 0.5]); D[:, 0] = sg * 0.12 * g
    elif name == 'eye_height':
        g = gauss(q, [0.5, 0.0, 0.0], [0.42, 0.35, 0.5]); D[:, 1] = 0.1 * g
    elif name == 'nose_length':
        g = gauss(q, [0.0, -0.6, 0.6], [0.3, 0.38, 0.35]); D[:, 2] = 0.24 * g; D[:, 1] = -0.05 * g
    elif name == 'nose_width':
        g = gauss(q, [0.0, -0.65, 0.45], [0.38, 0.28, 0.4]); D[:, 0] = x * 0.55 * g
    elif name == 'nose_bridge':
        g = gauss(q, [0.0, -0.15, 0.4], [0.22, 0.32, 0.35]); D[:, 2] = 0.12 * g
    elif name == 'lips':
        g = gauss(q, [0.0, -1.15, 0.35], [0.42, 0.16, 0.3]); D[:, 1] = np.sign(y + 1.15) * 0.05 * g; D[:, 2] = 0.06 * g
    elif name == 'mouth_width':
        g = gauss(q, [0.0, -1.15, 0.3], [0.5, 0.2, 0.35]); D[:, 0] = x * 0.3 * g
    elif name == 'brow_height':
        g = gauss(q, [0.5, 0.42, 0.1], [0.55, 0.22, 0.5]); D[:, 1] = 0.1 * g
    elif name == 'brow_depth':
        g = gauss(q, [0.5, 0.42, 0.1], [0.55, 0.22, 0.5]); D[:, 2] = 0.08 * g
    elif name == 'ears_size':
        c = np.array([1.3, 0.05, -1.45]); g = gauss(q, c, [0.3, 0.55, 0.45])
        rel = q.copy(); rel[:, 0] = np.abs(rel[:, 0]) - 1.3; rel -= [0, 0.05, -1.45]
        D = rel * 0.35 * g[:, None]; D[:, 0] = (D[:, 0] + 0.06 * g) * sg
    elif name == 'ears_point':
        g = gauss(q, [1.3, 0.45, -1.5], [0.25, 0.35, 0.35]); D[:, 1] = 0.5 * g; D[:, 2] = -0.18 * g; D[:, 0] = sg * 0.14 * g
    return D

def extra_field(name, q, kind):
    D = np.zeros_like(q)
    if name == 'beard_length' and kind == 'beard':
        D[:, 1] = np.minimum(q[:, 1] + 1.0, 0) * 0.7
        D[:, 2] = np.minimum(q[:, 1] + 1.0, 0) * -0.12
    elif name == 'beard_volume' and kind == 'beard':
        c = np.array([0.0, -0.8, -0.9]); D = (q - c) * 0.16
    elif name == 'hair_volume' and kind == 'hair':
        c = np.array([0.0, 0.2, -1.2]); D = (q - c) * 0.09
    return D

def add_morphs(pr, L, kind):
    """kind: head/eyes/brows/hair/beard. Возвращает (names, deltas)."""
    q = (pr['pos'] - L['E']) / L['d']
    names, deltas = [], []
    if kind == 'eyes':
        # глаза — жёсткие: смещаем каждый глаз как целое, масштаб — вокруг центра
        side = pr['pos'][:, 0] > L['E'][0]
        cents = np.where(side[:, None], pr['pos'][side].mean(0), pr['pos'][~side].mean(0))
        qc = (cents - L['E']) / L['d']
    for n in FACE_MORPHS + EXTRA_MORPHS:
        if n in EXTRA_MORPHS:
            D = extra_field(n, q, kind)
        elif kind == 'eyes':
            if n == 'eye_size':
                D = (pr['pos'] - cents) / L['d'] * 0.28
            else:
                D = field(n, qc)
        else:
            D = field(n, q)
        D = D * L['d']
        if np.abs(D).max() > 2e-4:
            names.append(n); deltas.append(D.astype(np.float32))
    return names, deltas

# ---------------------------------------------------------------- цвет кожи
def match_skin(src_path, ref_path, ref_box):
    """Подгоняет «тёмную» текстуру рук под светлый тон головы (поканально по среднему)."""
    a = np.asarray(Image.open(src_path).convert('RGB'), np.float32)
    r = np.asarray(Image.open(ref_path).convert('RGB').crop(ref_box), np.float32)
    ma = a.reshape(-1, 3); mr = r.reshape(-1, 3)
    skin_a = ma[(ma[:, 0] > ma[:, 2] + 15)]; skin_r = mr[(mr[:, 0] > mr[:, 2] + 15)]
    k = skin_r.mean(0) / np.maximum(skin_a.mean(0), 1)
    out = np.clip(a * k, 0, 255).astype(np.uint8)
    p = '/tmp/skin_matched_%s.png' % os.path.basename(src_path)
    Image.fromarray(out).save(p); return p

def eye_texture():
    im = np.asarray(Image.open(BTEX + 'T_Eye_Brown.png').convert('RGBA'), np.float32)
    rgb = im[:, :, :3]; mx = rgb.max(2); mn = rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1)
    h, w = sat.shape
    yy, xx = np.mgrid[0:h, 0:w]
    dark = (mx < 140) & (sat > 0.35)
    cy, cx = yy[dark].mean(), xx[dark].mean()
    rad = np.sqrt(((yy - cy) ** 2 + (xx - cx) ** 2))
    r_iris = np.percentile(rad[dark], 95)
    mask = np.clip((r_iris + 2 - rad) / 4, 0, 1)
    # радужка в серый (тон задаётся шейдером), остальное как есть
    lum = rgb.mean(2, keepdims=True)
    grey = np.clip(lum * 1.9, 0, 255)
    out = rgb * (1 - mask[:, :, None]) + grey * mask[:, :, None]
    o = np.concatenate([out, mask[:, :, None] * 255], 2).astype(np.uint8)
    p = os.path.join(TEXOUT, 'eyes_albedo.png'); Image.fromarray(o, 'RGBA').save(p)
    return {'albedo': 'tex/eyes_albedo.png'}

# ---------------------------------------------------------------- сборка
def build(G):
    gl = G.lower()[0]
    print('==', G)
    base = Gltf(BASE + f'Superhero_{G}_FullBody.gltf')
    ranger = Gltf(OUTF + f'{G}_Ranger.gltf')
    peasant = Gltf(OUTF + f'{G}_Peasant.gltf')
    L = landmarks(base)
    Lother = landmarks(Gltf(BASE + ('Superhero_Female_FullBody.gltf' if G == 'Male' else 'Superhero_Male_FullBody.gltf')))
    W = Writer()
    # ---- скелет из костюма Ranger (пропорции Regular)
    rj = ranger.j
    mesh_nodes = {i for i, n in enumerate(rj['nodes']) if 'mesh' in n}
    keep = [i for i in range(len(rj['nodes'])) if i not in mesh_nodes]
    nmap = {o: n for n, o in enumerate(keep)}
    for o in keep:
        n = {k: v for k, v in rj['nodes'][o].items() if k in ('name', 'translation', 'rotation', 'scale', 'children')}
        if 'children' in n:
            n['children'] = [nmap[c] for c in n['children'] if c in nmap]
            if not n['children']: del n['children']
        W.j['nodes'].append(n)
    arm = [i for i, n in enumerate(W.j['nodes']) if n['name'] == 'Armature'][0]
    W.j['scenes'][0]['nodes'] = [arm]
    name2node = {n['name']: i for i, n in enumerate(W.j['nodes'])}
    skins = {}
    def skin_for(g, key):
        if key in skins: return skins[key]
        names, ibm = skin_info(g)
        ia = W.add(ibm, typ='MAT4')
        W.j['skins'].append({'joints': [name2node[n] for n in names], 'inverseBindMatrices': ia, 'skeleton': name2node['root']})
        skins[key] = len(W.j['skins']) - 1; return skins[key]

    parts = []   # (name, prims, skin, kind, L)
    # ---- голова/торс из базового тела
    bmeshes = {n['name']: n['mesh'] for n in base.j['nodes'] if 'mesh' in n}
    body_name = [k for k in bmeshes if k not in ('Eyes', 'Eyebrows')][0]
    bpr = prims_of(base, bmeshes[body_name])[0]
    jn, _ = skin_info(base)
    head_j = [jn.index('Head'), jn.index('neck_01')]
    dom = bpr['joints'][np.arange(len(bpr['joints'])), bpr['weights'].argmax(1)]
    is_head_v = np.isin(dom, head_j)
    tri_head = is_head_v[bpr['idx']].all(1)
    head = subset(bpr, tri_head); torso = subset(bpr, ~tri_head)
    sk = skin_for(base, 'base')
    eyes = prims_of(base, bmeshes['Eyes'])[0]
    # ---- материалы / атласы
    mats = {}
    skin_src = {'Male': ('T_Superhero_Male_Ligh.png', 'T_Superhero_Male_Normal.png'),
                'Female': ('T_Superhero_Female_Light_BaseColor.png', 'T_Superhero_Female_Normal.png')}[G]
    mats['skin_head'] = pack([head], {'albedo': BTEX + skin_src[0], 'normal': BTEX + skin_src[1]}, f'head_{gl}', 1024, 1.0)
    if G == 'Male':
        mats['skin_body'] = pack([torso], {'albedo': BTEX + skin_src[0], 'normal': BTEX + skin_src[1]}, f'body_{gl}', 1024, 0.5)
    parts.append(('Face', [head], sk, 'head', L, 'skin_head'))
    if G == 'Male': parts.append(('Torso', [torso], sk, 'none', L, 'skin_body'))
    parts.append(('Eyes', [eyes], sk, 'eyes', L, 'eyes'))
    # ---- брови и причёски (обе версии бровей; причёски от обоих полов)
    hair_list = [('Brows_A', 'Eyebrows_Regular', 'brows'), ('Brows_B', 'Eyebrows_Female', 'brows'),
                 ('Hair_Buzzed', 'Hair_Buzzed', 'hair'), ('Hair_SimpleParted', 'Hair_SimpleParted', 'hair'),
                 ('Hair_Long', 'Hair_Long', 'hair'), ('Hair_Buns', 'Hair_Buns', 'hair'),
                 ('Hair_BuzzedFemale', 'Hair_BuzzedFemale', 'hair'), ('Beard', 'Hair_Beard', 'beard')]
    for out_name, src, kind in hair_list:
        hg = Gltf(HAIR + src + '.gltf')
        names, ibm = skin_info(hg)
        hb = np.linalg.inv(ibm[names.index('Head')].reshape(4, 4).T)[1, 3]
        Lsrc = L if abs(hb - (1.6 if G == 'Male' else 1.55)) < 0.02 else Lother
        parts.append((out_name, prims_of(hg, 0), skin_for(hg, src), kind, Lsrc, None))
    # ---- наряды
    for tag, og in (('Ranger', ranger), ('Peasant', peasant)):
        sko = skin_for(og, tag)
        for n in og.j['nodes']:
            if 'mesh' not in n: continue
            nm = n['name'].replace(f'{G}_', '')
            parts.append((nm, prims_of(og, n['mesh']), sko, 'none', L, None))
    # ---- материалы по исходным именам
    def mat_key(src_mat):
        if 'Eyes' in src_mat: return 'eyes'
        if 'Hair_1' in src_mat: return 'hair1'
        if 'Hair_2' in src_mat: return 'hair2'
        if 'Ranger' in src_mat: return 'ranger'
        if 'Peasant' in src_mat: return 'peasant'
        if 'Regular' in src_mat: return 'skin_arms'
        return 'skin_head'
    groups = {}
    for pn, prs, skn, kind, Ls, mk in parts:
        for pr in prs:
            pr['mkey'] = mk or mat_key(pr['mat'])
            groups.setdefault(pr['mkey'], []).append(pr)
    if 'skin_arms' in groups:
        reg = {'Male': 'T_Regular_Male', 'Female': 'T_Regular_Female'}[G]
        matched = match_skin(MTEX + f'Base/{reg}_Dark_BaseColor.png', BTEX + skin_src[0], (100, 100, 700, 700))
        mats['skin_arms'] = pack(groups['skin_arms'], {'albedo': matched, 'normal': MTEX + f'Base/{reg}_Normal.png'}, f'arms_{gl}', 512, 0.5)
    shared = {
        'hair1': lambda: pack(None, {'albedo': HTEX + 'T_Hair_1_BaseColor.png', 'normal': HTEX + 'T_Hair_1_Normal.png'}, 'hair1', 512, 1, keep_full=True),
        'hair2': lambda: pack(None, {'albedo': HTEX + 'T_Hair_2_BaseColor.png', 'normal': HTEX + 'T_Hair_2_Normal.png'}, 'hair2', 512, 1, keep_full=True),
        'ranger': lambda: pack(None, {'albedo': MTEX + 'Ranger/T_Ranger_BaseColor.png', 'normal': MTEX + 'Ranger/T_Ranger_Normal.png', 'orm': MTEX + 'Ranger/T_Ranger_ORM.png'}, 'ranger', 1024, 1, keep_full=True),
        'peasant': lambda: pack(None, {'albedo': MTEX + 'Peasant/T_Peasant_BaseColor.png', 'normal': MTEX + 'Peasant/T_Peasant_Normal.png', 'orm': MTEX + 'Peasant/T_Peasant_ORM.png'}, 'peasant', 1024, 1, keep_full=True),
        'eyes': eye_texture,
    }
    for k, fn in shared.items():
        if k in groups and k not in mats:
            if os.path.exists(os.path.join(TEXOUT, f'{k}_albedo.png')) and G == 'Female':
                mats[k] = {c: f'tex/{k}_{c}.png' for c in ('albedo', 'normal', 'orm') if os.path.exists(os.path.join(TEXOUT, f'{k}_{c}.png'))}
            else:
                mats[k] = fn()
    mat_index = {}
    for k, tex in mats.items():
        m = {'name': k, 'pbrMetallicRoughness': {'metallicFactor': 0.0, 'roughnessFactor': 0.62}}
        if 'albedo' in tex: m['pbrMetallicRoughness']['baseColorTexture'] = {'index': W.add_image(tex['albedo'])}
        if 'normal' in tex: m['normalTexture'] = {'index': W.add_image(tex['normal'])}
        if 'orm' in tex:
            m['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': W.add_image(tex['orm'])}
            m['pbrMetallicRoughness']['metallicFactor'] = 1.0; m['pbrMetallicRoughness']['roughnessFactor'] = 1.0
        if k == 'eyes': m['alphaMode'] = 'OPAQUE'
        W.j['materials'].append(m); mat_index[k] = len(W.j['materials']) - 1
    # ---- меши
    report = []
    for pn, prs, skn, kind, Ls, mk in parts:
        mesh = {'name': pn, 'primitives': []}
        tnames = None
        for pr in prs:
            attrs = {'POSITION': W.add(pr['pos'], 34962, minmax=True), 'NORMAL': W.add(pr['nrm'], 34962),
                     'TEXCOORD_0': W.add(pr['uv'], 34962), 'JOINTS_0': W.add(pr['joints'], 34962),
                     'WEIGHTS_0': W.add(pr['weights'], 34962)}
            prim = {'attributes': attrs, 'indices': W.add(pr['idx'].reshape(-1), 34963), 'material': mat_index[pr['mkey']]}
            if kind in ('head', 'eyes', 'brows', 'hair', 'beard'):
                names, deltas = add_morphs(pr, Ls, kind)
                if tnames is None: tnames = names
                # у всех примитивов меша должен быть одинаковый набор морфов
                full = []
                for n in tnames:
                    D = deltas[names.index(n)] if n in names else np.zeros_like(pr['pos'])
                    full.append({'POSITION': W.add(D, 34962, minmax=True)})
                prim['targets'] = full
            mesh['primitives'].append(prim)
        if tnames:
            mesh['extras'] = {'targetNames': tnames}; mesh['weights'] = [0.0] * len(tnames)
        W.j['meshes'].append(mesh)
        W.j['nodes'].append({'name': pn, 'mesh': len(W.j['meshes']) - 1, 'skin': skn})
        W.j['nodes'][arm].setdefault('children', []).append(len(W.j['nodes']) - 1)
        tris = sum(len(p['idx']) for p in prs)
        report.append((pn, tris, len(tnames or [])))
    path = os.path.join(OUT, f'human_{gl}.gltf')
    W.save(path)
    for r in report: print('   %-28s tris %6d morphs %d' % r)
    print('   ->', path, os.path.getsize(path.replace('.gltf', '.bin')) // 1024, 'KB bin')

if __name__ == '__main__':
    for G in ('Male', 'Female'):
        build(G)
