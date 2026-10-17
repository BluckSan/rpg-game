import sys; sys.path.insert(0,'/workspace/logo')
from emblem import *
from PIL import Image
G='/workspace/rpg-godot/'
em=Image.open(OUT+'emblem_1024.png'); sm=Image.open(OUT+'emblem_simple_1024.png'); full=Image.open(OUT+'logo_full.png')
import os
os.makedirs(G+'assets/ui/brand',exist_ok=True)
# main-menu logo
lw=1100; full.resize((lw,int(full.height*lw/full.width)),Image.LANCZOS).save(G+'assets/ui/brand/logo.png')
em.resize((512,512),Image.LANCZOS).save(G+'assets/ui/brand/emblem.png')
# boot splash 1920x1080
sp=bg(1080,rounded=False).resize((1920,1080),Image.LANCZOS)
y,x=np.mgrid[0:1080,0:1920]; r=np.hypot((x-960)/1080,(y-500)/1080); t=np.clip(r/0.9,0,1)[...,None]
sp=to_img(lin('#24134a')*(1-t)+lin('#050409')*t,np.ones((1080,1920)))
lg=full.resize((900,int(full.height*900/full.width)),Image.LANCZOS)
sp.alpha_composite(lg,((1920-lg.width)//2,(1080-lg.height)//2-30))
sp.convert('RGB').save(G+'assets/ui/brand/splash.png')
# app icon (rounded square) from simple emblem, emblem fills ~92%
def app_icon(S, rounded=True, fill=0.94, src=sm):
    b=bg(S,rounded=rounded); e=src.resize((int(S*fill),int(S*fill)),Image.LANCZOS)
    b.alpha_composite(e,((S-e.width)//2,(S-e.height)//2)); return b
ic=app_icon(1024); ic.save(G+'icon.png')
# Windows .ico: small sizes from the simple emblem, sharpened
sizes=[16,24,32,48,64,128,256]
ims=[]
for s in sizes:
    big=app_icon(1024, rounded=True, fill=1.0 if s<=32 else 0.94, src=sm if s<=128 else em)
    im=big.resize((s,s),Image.LANCZOS)
    if s<=48: im=im.filter(ImageFilter.UnsharpMask(radius=1,percent=80,threshold=0))
    ims.append(im)
ims[-1].save(G+'icon.ico',sizes=[(s,s) for s in sizes],append_images=ims[:-1])
# Android
os.makedirs(G+'assets/icon',exist_ok=True)
app_icon(192*4).resize((192,192),Image.LANCZOS).save(G+'assets/icon/android_main_192.png')
fg=Image.new('RGBA',(432,432),(0,0,0,0)); e=sm.resize((300,300),Image.LANCZOS); fg.alpha_composite(e,(66,66)); fg.save(G+'assets/icon/android_fg_432.png')
bgi=bg(432,rounded=False); bgi.save(G+'assets/icon/android_bg_432.png')
a=np.asarray(e,float)[...,3]/255; mono=Image.new('RGBA',(432,432),(0,0,0,0)); mono.alpha_composite(to_img(np.ones((300,300,3)),a),(66,66)); mono.save(G+'assets/icon/android_mono_432.png')
# previews for the report
prev=Image.new('RGBA',(1500,620),(24,22,30,255))
from PIL import ImageDraw
d=ImageDraw.Draw(prev); ft=ImageFont.truetype('/workspace/rpg-godot/fonts/Rubik.ttf',22)
prev.alpha_composite(ic.resize((360,360),Image.LANCZOS),(20,40)); d.text((20,8),'Иконка 1024 (360 px)',font=ft,fill='white')
# adaptive masks: circle, squircle, rounded
comp=bgi.copy(); comp.alpha_composite(fg)
for i,(nm,shape) in enumerate([('круг','c'),('скругл.','r'),('капля','t')]):
    m=Image.new('L',(432,432),0); dm=ImageDraw.Draw(m)
    if shape=='c': dm.ellipse([0,0,431,431],fill=255)
    elif shape=='r': dm.rounded_rectangle([0,0,431,431],radius=90,fill=255)
    else: dm.rounded_rectangle([0,0,431,431],radius=216,fill=255); dm.rectangle([216,216,431,431],fill=255)
    c=comp.copy(); c.putalpha(m); c=c.resize((200,200),Image.LANCZOS)
    prev.alpha_composite(c,(420+i*220,40)); d.text((420+i*220,8),'Android: '+nm,font=ft,fill='white')
x=420
for s in (16,24,32,48,64):
    im=ims[sizes.index(s)]; prev.alpha_composite(im,(x,330)); x+=s+20
d.text((420,290),'.ico 16/24/32/48/64 (1:1)',font=ft,fill='white')
x=420
for s in (48,72,96,144):
    prev.alpha_composite(comp.resize((s,s),Image.LANCZOS),(x,400)); x+=s+20
d.text((420,560),'Адаптивная иконка 48–144 px',font=ft,fill='white')
prev.save('/workspace/rpg-shots/v051/brand_icons.png')
full_bg=Image.new('RGBA',full.size,(14,10,22,255)); full_bg.alpha_composite(full); full_bg.convert('RGB').resize((full.width*2//3,full.height*2//3)).save('/workspace/rpg-shots/v051/brand_logo.png')
print('ok')
