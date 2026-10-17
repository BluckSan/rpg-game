"""Генератор текстур интерфейса (рамки, полосы, кольца кнопок). python3 tools/gen_ui.py"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, os
OUT = 'assets/ui'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(3)
GOLD = (196, 150, 72, 255); GOLD_D = (110, 78, 34, 255); GOLD_L = (240, 205, 130, 255)

def leather(w, h, base=(30, 23, 18), var=7):
    n = rng.normal(0, var, (h, w, 1))
    # мягкая крупная фактура
    big = Image.fromarray(np.uint8(np.clip(rng.normal(128, 40, (h // 8 + 1, w // 8 + 1)), 0, 255))).resize((w, h), Image.BICUBIC)
    b = (np.asarray(big, dtype=float)[..., None] - 128) * 0.08
    a = np.clip(np.array(base, float)[None, None, :] + n + b, 0, 255)
    # виньетка
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) / (min(w, h) * 0.5)
    a *= (0.75 + 0.25 * np.clip(d * 2.5, 0, 1))[..., None]
    return Image.fromarray(np.uint8(a)).convert('RGBA')

def diamond(d, cx, cy, r, fill, outline=None):
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=fill, outline=outline)

def frame(name, w, h, base, border=3, inset=7, ornament=True, alpha=245):
    im = leather(w, h, base)
    im.putalpha(alpha)
    d = ImageDraw.Draw(im)
    for i in range(border):
        c = GOLD_L if i == 0 else (GOLD if i < border - 1 else GOLD_D)
        d.rounded_rectangle([i, i, w - 1 - i, h - 1 - i], radius=10 - i, outline=c)
    d.rounded_rectangle([inset, inset, w - 1 - inset, h - 1 - inset], radius=5, outline=(120, 90, 45, 200))
    if ornament:
        for cx, cy in [(inset, inset), (w - 1 - inset, inset), (inset, h - 1 - inset), (w - 1 - inset, h - 1 - inset)]:
            diamond(d, cx, cy, 7, GOLD, GOLD_D)
            diamond(d, cx, cy, 3, GOLD_L)
        for cx, cy in [(w // 2, 2), (w // 2, h - 3)]:
            diamond(d, cx, cy, 5, GOLD, GOLD_D)
    # скругление внешних углов
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=10, fill=255)
    a = np.minimum(np.asarray(im.getchannel('A')), np.asarray(mask))
    im.putalpha(Image.fromarray(a))
    im.save(f'{OUT}/{name}.png')

frame('panel', 128, 128, (30, 24, 19))
frame('panel_dark', 128, 128, (16, 13, 11), alpha=235)
frame('slot', 64, 64, (22, 19, 17), border=2, inset=5, ornament=False)
frame('tooltip', 96, 96, (20, 16, 13), border=2, inset=5, ornament=True, alpha=248)

# кнопка: светлая заливка (тонируется modulate) + тёмная фаска
def button(name, w=96, h=64):
    im = Image.new('RGBA', (w, h))
    a = np.zeros((h, w, 4))
    yy = np.linspace(0, 1, h)[:, None]
    g = 225 - 70 * yy  # градиент сверху вниз
    a[..., 0] = g; a[..., 1] = g; a[..., 2] = g; a[..., 3] = 255
    a[:, :, :3] += rng.normal(0, 4, (h, w, 1))
    im = Image.fromarray(np.uint8(np.clip(a, 0, 255)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=9, outline=(70, 60, 50, 255), width=2)
    d.rounded_rectangle([3, 3, w - 4, h - 4], radius=7, outline=(255, 245, 225, 160), width=1)
    d.line([(6, 4), (w - 7, 4)], fill=(255, 255, 255, 120))
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=9, fill=255)
    im.putalpha(mask)
    im.save(f'{OUT}/{name}.png')
button('button')

# полосы: рамка и глянцевая заливка (тонируется)
def bar_fill():
    w, h = 64, 32
    yy = np.linspace(0, 1, h)[:, None]
    g = 150 + 105 * np.clip(1 - np.abs(yy - 0.3) * 2.2, 0, 1)
    g = g - 40 * (yy > 0.6) * (yy - 0.6) * 2.5
    a = np.zeros((h, w, 4)); a[..., :3] = np.repeat(g, w, 1)[..., None]; a[..., 3] = 255
    Image.fromarray(np.uint8(np.clip(a, 0, 255))).save(f'{OUT}/bar_fill.png')
bar_fill()
def bar_bg():
    w, h = 64, 32
    im = Image.new('RGBA', (w, h), (12, 9, 8, 230))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=7, outline=GOLD, width=2)
    d.rounded_rectangle([2, 2, w - 3, h - 3], radius=5, outline=GOLD_D, width=1)
    im.save(f'{OUT}/bar_bg.png')
bar_bg()

# кольцо для круглых кнопок умений
def ring(name, s=256):
    big = s * 2
    im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, big - 1, big - 1], fill=(20, 15, 12, 255))
    d.ellipse([6, 6, big - 7, big - 7], fill=GOLD_D)
    d.ellipse([12, 12, big - 13, big - 13], fill=GOLD)
    d.ellipse([20, 20, big - 21, big - 21], fill=GOLD_L)
    d.ellipse([26, 26, big - 27, big - 27], fill=GOLD_D)
    d.ellipse([32, 32, big - 33, big - 33], fill=(0, 0, 0, 0))
    for k in range(4):
        import math
        a = math.pi / 4 + k * math.pi / 2
        cx = big / 2 + math.cos(a) * (big / 2 - 19); cy = big / 2 + math.sin(a) * (big / 2 - 19)
        diamond(d, cx, cy, 16, GOLD_L, GOLD_D)
    im = im.resize((s, s), Image.LANCZOS)
    im.save(f'{OUT}/{name}.png')
ring('skill_ring')

# мини-карта: круглая рамка-компас
def compass(s=320):
    big = s * 2
    im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, big - 1, big - 1], fill=(20, 15, 12, 255))
    d.ellipse([8, 8, big - 9, big - 9], fill=GOLD_D)
    d.ellipse([14, 14, big - 15, big - 15], fill=GOLD)
    d.ellipse([22, 22, big - 23, big - 23], fill=GOLD_D)
    d.ellipse([28, 28, big - 29, big - 29], fill=(0, 0, 0, 0))
    im = im.resize((s, s), Image.LANCZOS)
    im.save(f'{OUT}/compass_ring.png')
compass()
print('ok', sorted(os.listdir(OUT)))
