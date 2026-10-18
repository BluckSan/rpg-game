"""v0.6.0: массивы текстур (Texture2DArray) из ambientCG CC0 1K:
assets/terrain/layers.jpg — цвет 7 слоёв земли 1024² (с запечённым AO), assets/terrain/normals.jpg — RG нормаль (GL) + B высота;
assets/real/surf/albedo.jpg + normal.jpg — 13 материалов построек/подземелий 512² (кладка, плиты, доски, брус, черепица, штукатурка,
ткань, металл, скала, трава, солома, бутовый камень, грунт)."""
import glob
import numpy as np
from PIL import Image
A = '/workspace/acg'
def ld(k, part, size, mode='RGB'):
    f = glob.glob(f'{A}/{k}/*_{part}.jpg') + glob.glob(f'{A}/{k}/*_{part}.png')
    if not f: return None
    return Image.open(f[0]).convert(mode).resize((size, size), Image.LANCZOS)
def build(ids, size, out_a, out_n, ao_mul=0.55):
    al, nr = [], []
    for k in ids:
        c = np.array(ld(k, 'Color', size)).astype(float)
        ao = ld(k, 'AmbientOcclusion', size, 'L')
        if ao is not None: c *= (1 - ao_mul) + ao_mul * (np.array(ao).astype(float)[..., None] / 255.0)
        al.append(np.clip(c, 0, 255).astype('uint8'))
        n = np.array(ld(k, 'NormalGL', size)).astype('uint8')
        h = ld(k, 'Displacement', size, 'L')
        h = np.array(h) if h is not None else np.full((size, size), 128, 'uint8')
        # высоту растянуть на полный диапазон — для смешения слоёв по высоте
        hf = h.astype(float); hf = (hf - hf.min()) / max(1.0, hf.max() - hf.min()) * 255
        n[..., 2] = hf.astype('uint8')
        nr.append(n)
    Image.fromarray(np.concatenate(al, 0)).save(out_a, quality=92)
    Image.fromarray(np.concatenate(nr, 0)).save(out_n, quality=95)
    print(out_a, len(ids))
build(['Grass004', 'Ground037', 'Ground048', 'Ground080', 'Ground054', 'Snow006', 'Rock030'], 1024,
      '/workspace/rpg-godot/assets/terrain/layers.jpg', '/workspace/rpg-godot/assets/terrain/normals.jpg', 0.5)
SURF = ['Bricks076A', 'PavingStones131', 'Planks023A', 'Wood051', 'RoofingTiles006', 'Plaster001', 'Fabric030', 'Metal032',
        'Rock022', 'Grass004', 'ThatchedRoof001A', 'Bricks102', 'Ground054']
build(SURF, 512, '/workspace/rpg-godot/assets/real/surf/albedo.jpg', '/workspace/rpg-godot/assets/real/surf/normal.jpg', 0.6)
