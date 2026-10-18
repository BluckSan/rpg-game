"""Poly Haven (CC0) 1K → assets/real/tex: <id>_d.jpg (цвет), _n.jpg (нормали GL), _orm.jpg (AO/шероховатость/металл).
Размер по важности: крупные камни/постройки 1024 цвет, остальное 512, мелочь 256. Пишет .import (VRAM, мипмапы)."""
import json, os, glob, sys
from PIL import Image
SRC = '/workspace/realism_src/ph'
OUT = '/workspace/rpg-godot/assets/real/tex'
SIZES = {  # id: (цвет, нормали/orm)
  'rock_moss_set_01': (1024, 512), 'rock_moss_set_02': (1024, 512), 'boulder_01': (512, 512), 'namaqualand_boulder_02': (512, 512),
  'namaqualand_boulder_03': (512, 512), 'namaqualand_boulder_04': (512, 512), 'gothic_statue': (1024, 512),
  'dandelion_01': (256, 256), 'nettle_plant': (256, 256), 'shrub_sorrel_01': (256, 256), 'weed_plant_02': (256, 256),
  'periwinkle_plant': (256, 256), 'grass_medium_02': (256, 256), 'wooden_bucket_01': (256, 256), 'wooden_axe_03': (256, 256),
  'wooden_stool_01': (256, 256), 'wooden_lantern_01': (256, 256), 'wicker_basket_01': (256, 256), 'spinning_wheel_01': (256, 256),
  'WoodenTable_01': (256, 256), 'stone_fire_pit': (512, 256), 'dry_branches_medium_01': (256, 256),
}
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/real/tex/{f}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""
ids = sys.argv[1:]
for i in ids:
    cs, ns = SIZES.get(i, (512, 512))
    for tf in glob.glob(f'{SRC}/{i}/textures/*.jpg'):
        b = os.path.basename(tf)
        stem = b.rsplit('_1k', 1)[0]           # e.g. shrub_02_diff
        part = stem.rsplit('_', 1)[-1]
        if stem.endswith('_nor_gl'): suf, sz = 'n', ns; stem = stem[:-len('_nor_gl')]
        elif part == 'diff': suf, sz = 'd', cs; stem = stem[:-5]
        elif part == 'arm': suf, sz = 'orm', ns; stem = stem[:-4]
        else: print('skip', b); continue
        name = f'{stem}_{suf}.jpg'
        im = Image.open(tf).convert('RGB')
        if im.size[0] > sz: im = im.resize((sz, sz), Image.LANCZOS)
        im.save(f'{OUT}/{name}', quality=90)
        open(f'{OUT}/{name}.import', 'w').write(IMPORT.format(f=name))
print('ok', len(os.listdir(OUT)))
