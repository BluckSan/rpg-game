"""v0.6.0: текстуры-карточки листвы/травы из CC0-атласов ambientCG (Foliage*, LeafSet*) → assets/real/foliage/*.png (RGBA).
grass_card — пучок травинок; leaf_card — ветка с листьями (лиственные); needle_card — лапа хвои (ель/сосна);
twig_card — голые ветки (мёртвые деревья, топи). Цвета/формы — из фотосканов, хвоя дорисовывается штрихами."""
import random, math, glob
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
A = '/workspace/acg'
OUT = '/workspace/rpg-godot/assets/real/foliage'
rnd = random.Random(7)

def rgba(k):
    c = Image.open(glob.glob(f'{A}/{k}/*_Color.png')[0]).convert('RGB')
    o = Image.open(glob.glob(f'{A}/{k}/*_Opacity.png')[0]).convert('L').resize(c.size)
    im = c.copy(); im.putalpha(o); return im

def pieces(k, min_area=400):
    """вырезать отдельные элементы атласа (травинки/листья) по связным областям непрозрачности"""
    im = rgba(k); a = np.array(im.split()[3]) > 40
    from scipy import ndimage
    lab, n = ndimage.label(ndimage.binary_dilation(a, iterations=2))
    out = []
    for sl in ndimage.find_objects(lab):
        h = sl[0].stop - sl[0].start; w = sl[1].stop - sl[1].start
        if h * w < min_area: continue
        out.append(im.crop((sl[1].start, sl[0].start, sl[1].stop, sl[0].stop)))
    return out

def tone(im, f=1.0, sat=1.0, hue_shift=None):
    if f != 1.0: im = Image.merge('RGBA', [*ImageEnhance.Brightness(im.convert('RGB')).enhance(f).split(), im.split()[3]])
    if sat != 1.0: im = Image.merge('RGBA', [*ImageEnhance.Color(im.convert('RGB')).enhance(sat).split(), im.split()[3]])
    return im

def bleed(card):
    """цвет под прозрачными пикселями = размытый цвет соседей (без тёмной каймы на мипмапах)"""
    a = card.split()[3]
    rgb = card.convert('RGB')
    blur = rgb
    for r in (2, 6, 16, 40):
        b = rgb.filter(ImageFilter.GaussianBlur(r))
        ab = a.filter(ImageFilter.GaussianBlur(r))
        arr = np.array(b).astype(float); aa = np.array(ab).astype(float)[..., None] / 255.0
        arr = np.where(aa > 0.01, arr / np.maximum(aa, 0.01), 0)
        blur = Image.composite(blur, Image.fromarray(np.clip(arr, 0, 255).astype('uint8')), a.point(lambda v: 255 if v > 0 else 0))
    blur.putalpha(a); return blur

# ---------- трава ----------
def grass_card():
    W, H = 1024, 512
    card = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    blades = []
    for k in ['Foliage001', 'Foliage006', 'Foliage008', 'Foliage004', 'Foliage007']:
        ps = pieces(k)
        for p in ps:
            if p.size[1] < p.size[0]: p = p.rotate(90, expand=True)   # горизонтальные травинки — вертикально
            blades.append(p)
    heads = pieces('Foliage002') + pieces('Foliage003')
    for i in range(150):
        b = rnd.choice(blades)
        h = rnd.uniform(0.45, 1.0) * H * (1.0 - abs(rnd.gauss(0, 0.25)) * 0.5)
        sc = h / b.size[1]; w = max(4, int(b.size[0] * sc * rnd.uniform(0.7, 1.1)))
        bb = b.resize((w, int(h)), Image.LANCZOS)
        bb = bb.rotate(rnd.uniform(-14, 14), expand=True, resample=Image.BICUBIC)
        bb = tone(bb, rnd.uniform(0.7, 1.15), rnd.uniform(0.85, 1.15))
        x = int(rnd.gauss(W / 2, W * 0.2) - bb.size[0] / 2)
        card.alpha_composite(bb, (max(0, min(W - bb.size[0], x)), H - bb.size[1]))
    for i in range(10):
        b = rnd.choice(heads); h = rnd.uniform(0.6, 0.95) * H
        sc = h / b.size[1]; bb = b.resize((max(4, int(b.size[0] * sc)), int(h)), Image.LANCZOS)
        bb = bb.rotate(rnd.uniform(-10, 10), expand=True, resample=Image.BICUBIC)
        x = int(rnd.uniform(0.15, 0.85) * W - bb.size[0] / 2)
        card.alpha_composite(bb, (max(0, min(W - bb.size[0], x)), H - bb.size[1]))
    # затенение к основанию
    arr = np.array(card).astype(float)
    y = np.linspace(0, 1, H)[:, None]
    arr[..., :3] *= (0.45 + 0.55 * (1 - y ** 2.2))[..., None]
    card = Image.fromarray(np.clip(arr, 0, 255).astype('uint8'))
    bleed(card).save(f'{OUT}/grass_card.png')

# ---------- лиственные ----------
def branch_lines(d, x0, y0, ang, ln, wdt, depth, pts, col):
    x1 = x0 + math.cos(ang) * ln; y1 = y0 + math.sin(ang) * ln
    d.line([(x0, y0), (x1, y1)], fill=col, width=max(1, int(wdt)))
    n = 5 if depth else 3
    for i in range(n):
        t = (i + 1) / (n + 1)
        pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, ang + rnd.choice([-1, 1]) * rnd.uniform(0.6, 1.2)))
    pts.append((x1, y1, ang))
    if depth > 0:
        for i in range(3):
            t = rnd.uniform(0.3, 0.85); s = rnd.choice([-1, 1])
            branch_lines(d, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, ang + s * rnd.uniform(0.5, 1.0), ln * rnd.uniform(0.45, 0.65), wdt * 0.6, depth - 1, pts, col)

def leaf_card(name, leaf_sets, n_leaves, leaf_px, hue=None):
    W = H = 1024
    card = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    pts = []
    # ветка входит снизу-по центру, ветвится вверх
    for bi in range(3):
        branch_lines(d, W * 0.5, H * 0.98, -math.pi / 2 + (bi - 1) * 0.55 + rnd.uniform(-0.1, 0.1), H * 0.5, 12, 2, pts, (74, 58, 42, 255))
    leaves = []
    for k in leaf_sets: leaves += pieces(k, 3000)
    rnd.shuffle(pts)
    placed = 0
    for i in range(n_leaves):
        x, y, a = pts[i % len(pts)]
        x += rnd.gauss(0, 18); y += rnd.gauss(0, 18)
        lf = rnd.choice(leaves)
        s = leaf_px * rnd.uniform(0.75, 1.2) / max(lf.size)
        lf = lf.resize((max(4, int(lf.size[0] * s)), max(4, int(lf.size[1] * s))), Image.LANCZOS)
        # лист растёт от черешка (низ картинки) наружу вдоль направления a
        rot = -math.degrees(a) - 90 + rnd.uniform(-35, 35)
        lf = lf.rotate(rot, expand=True, resample=Image.BICUBIC)
        r = math.hypot(x - W / 2, y - H * 0.45) / (W * 0.5)
        lf = tone(lf, rnd.uniform(0.62, 1.1) * (0.8 + 0.25 * min(r, 1.0)), rnd.uniform(0.85, 1.1))
        cx = int(x + math.cos(a) * lf.size[0] * 0.3 - lf.size[0] / 2); cy = int(y + math.sin(a) * lf.size[1] * 0.3 - lf.size[1] / 2)
        if 0 <= cx < W - lf.size[0] and 0 <= cy < H - lf.size[1]:
            card.alpha_composite(lf, (cx, cy)); placed += 1
    if hue:
        arr = np.array(card).astype(float); arr[..., :3] *= np.array(hue)[None, None, :]
        card = Image.fromarray(np.clip(arr, 0, 255).astype('uint8'))
    bleed(card).save(f'{OUT}/{name}.png')
    print(name, placed)

# ---------- хвоя ----------
def needle_card(name, base, spread=1.0, droop=0.0, density=1.0):
    W, H = 1024, 1024
    card = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    # главная ось лапы — вертикально (снизу вверх), боковые веточки ёлочкой
    def twig(x0, y0, ang, ln, w, depth):
        segs = 14
        pts = []
        for i in range(segs + 1):
            t = i / segs
            a = ang + droop * t * t
            pts.append((x0 + math.cos(a) * ln * t, y0 + math.sin(a) * ln * t))
        for i in range(segs):
            t = i / segs
            p0, p1 = pts[i], pts[i + 1]
            # хвоинки по обе стороны
            for k in range(int(16 * density)):
                tt = rnd.random(); px = p0[0] + (p1[0] - p0[0]) * tt; py = p0[1] + (p1[1] - p0[1]) * tt
                sa = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
                na = sa + rnd.choice([-1, 1]) * rnd.uniform(0.6, 1.25) * spread
                nl = rnd.uniform(22, 40) * (1.0 - t * 0.45) * (1.25 if depth == 0 else 1.0)
                c = [int(v * rnd.uniform(0.7, 1.25)) for v in base]
                d.line([(px, py), (px + math.cos(na) * nl, py + math.sin(na) * nl)], fill=(*c, 255), width=rnd.choice([2, 3]))
        d.line(pts, fill=(70, 52, 36, 255), width=max(2, int(w)))
        if depth > 0:
            for i in range(1, segs - 1):
                t = i / segs
                for s in (-1, 1):
                    twig(pts[i][0], pts[i][1], ang + s * rnd.uniform(0.75, 1.0), ln * (0.40 - 0.28 * t), w * 0.5, depth - 1)
    twig(W * 0.5, H * 0.99, -math.pi / 2, H * 0.92, 9, 1)
    arr = np.array(card).astype(float)
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.hypot((xx - W / 2) / (W / 2), (yy - H) / H)
    
    arr[..., :3] *= (0.6 + 0.4 * np.clip(r, 0, 1))[..., None]
    card = Image.fromarray(np.clip(arr, 0, 255).astype('uint8'))
    bleed(card.filter(ImageFilter.SMOOTH)).save(f'{OUT}/{name}.png')

def twig_card():
    W = H = 1024
    card = Image.new('RGBA', (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(card); pts = []
    for i in range(3):
        branch_lines(d, W * (0.35 + 0.15 * i), H * 0.99, -math.pi / 2 + rnd.uniform(-0.4, 0.4), H * 0.6, 12, 2, pts, (62, 54, 46, 255))
    bleed(card).save(f'{OUT}/twig_card.png')

grass_card()
leaf_card('leaf_card', ['LeafSet024', 'LeafSet005'], 520, 78)
leaf_card('leaf_card_autumn', ['LeafSet024'], 480, 78, hue=(1.5, 0.95, 0.45))
needle_card('needle_card', (40, 66, 34), 1.0, 0.25, 1.0)
needle_card('pine_card', (56, 78, 36), 0.55, 0.0, 1.3)
twig_card()
for f in glob.glob(f'{OUT}/*.png'):
    im = Image.open(f); print(f, im.size)
