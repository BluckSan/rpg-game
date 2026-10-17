from PIL import Image
import colorsys, glob, os
def find(n):
    r=[p for p in glob.glob('/workspace/icons_src/**/'+n+'.png',recursive=True) if 'border' not in p]
    assert r, n; return r[0]
def recolor(im, hue=None, sat=1.0, val=1.0, hue_shift=None):
    im=im.convert('RGBA'); px=im.load()
    for y in range(im.height):
        for x in range(im.width):
            r,g,b,a=px[x,y]
            if a==0 or (r,g,b)==(0,0,0): continue
            h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
            if hue is not None: h=hue
            if hue_shift is not None: h=(h+hue_shift)%1
            s=min(1,s*sat); v=min(1,v*val)
            rr,gg,bb=colorsys.hsv_to_rgb(h,s,v); px[x,y]=(int(rr*255),int(gg*255),int(bb*255),a)
    return im
# type -> 3 tiers: (source, recolor-kwargs or None)
M={
 'sword':[('sword1',None),('sword3',None),('sword5',{'hue':0.53,'sat':0.35})],
 'axe':[('axe2',None),('axe1',None),('axe4',None)],
 'bow':[('bow1',None),('bow2',None),('bow4',None)],
 'staff':[('staff1',None),('stave_4',None),('stave_5',None)],
 'plate':[('chainmail_jacket',None),('platemail',None),('breastplate',None)],
 'leather':[('leather_jacket',None),('studded_jacket',None),('studded_jacket_alt',None)],
 'robe':[('cloth_robe',None),('cloth_robe',{'hue':0.58,'sat':0.9}),('cloth_robe',{'hue':0.76,'sat':0.95,'val':1.05})],
 'cloak':[('cloak',{'hue':0.08,'sat':0.6,'val':0.85}),('cloak',{'hue':0.30,'sat':0.6}),('cloak',None)],
 'helm':[('platemail_helmet',None),('horned_helmet',None),('close_helmet',None)],
 'hood':[('cloth_hood',None),('cloth_hood',{'hue':0.27,'sat':0.55}),('cloth_hood',{'hue':0.72,'sat':0.35,'val':0.6})],
 'hat':[('hat_t0',None),('hat_t1',None),('hat_t2',None)],
 'circlet':[('circlet_t0',None),('circlet_t1',None),('circlet_t2',None)],
 'ring':[('copper_ring',None),('silver_ring',None),('gold_ring',None)],
 'gloves':[('leather_gloves',None),('iron_bracers',None),('gauntlets',None)],
 'boots':[('leather_boots',None),('studded_boots',None),('greaves',None)],
 'amulet':[('tile046',None),('tile047',None),('tile049',None)],
 'belt':[('belt_t0',None),('belt_t1',None),('belt_t2',None)],
}
EXTRA={'potion':('potion_full_1',None),'dust':('crystal_blue',None)}
OUT='/workspace/rpg-godot/assets/items/'
def emit(src,kw,name):
    im=Image.open(find(src)).convert('RGBA')
    if im.size!=(32,32): im=im.resize((32,32),Image.NEAREST)
    if kw: im=recolor(im,**kw)
    im.resize((128,128),Image.NEAREST).save(OUT+name+'.png')
    return im
sheet=Image.new('RGBA',(3*72+150,len(M)*72),(30,26,22,255))
from PIL import ImageDraw
d=ImageDraw.Draw(sheet)
for i,(t,tiers) in enumerate(M.items()):
    d.text((6,i*72+30),t,fill='white')
    for k,(src,kw) in enumerate(tiers):
        im=emit(src,kw,'%s_t%d'%(t,k))
        if k==0: emit(src,kw,t)
        big=im.resize((64,64),Image.NEAREST); sheet.paste(big,(150+k*72,i*72+4),big)
for n,(src,kw) in EXTRA.items(): emit(src,kw,n)
sheet.save('/tmp/item_sheet.png'); print('done')
