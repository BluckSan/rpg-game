# «Осколки Эфира» emblem / wordmark / icons. Original artwork made procedurally for the game.
import numpy as np, math, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
R=random.Random(7)
OUT='/workspace/logo/out/'
def lin(c): return np.array([int(c[1:3],16),int(c[3:5],16),int(c[5:7],16)],float)/255
def to_img(rgb,a):
    arr=np.dstack([np.clip(rgb,0,1)*255,np.clip(a,0,1)*255]).astype(np.uint8); return Image.fromarray(arr,'RGBA')
def mask_poly(S,pts,scale=1.0):
    m=Image.new('L',(S,S),0); ImageDraw.Draw(m).polygon([(x*S,y*S) for x,y in pts],fill=255); return m
def over(base,top): return Image.alpha_composite(base,top)
def glow(mask,color,radius,strength=1.0):
    b=mask.filter(ImageFilter.GaussianBlur(radius)); a=np.asarray(b,float)/255*strength
    S=mask.size[0]; rgb=np.ones((S,S,3))*lin(color); return to_img(rgb,a)
def colorize(mask,rgb_arr): return to_img(rgb_arr,np.asarray(mask,float)/255)
def grad_lin(S,c0,c1,p0,p1):
    y,x=np.mgrid[0:S,0:S]/S; d=np.array(p1)-np.array(p0)
    t=((x-p0[0])*d[0]+(y-p0[1])*d[1])/(d@d); t=np.clip(t,0,1)[...,None]
    return lin(c0)*(1-t)+lin(c1)*t

def emblem(S=2048, simple=False, ring=True):
    img=Image.new('RGBA',(S,S),(0,0,0,0))
    y,x=np.mgrid[0:S,0:S]; cx=cy=S/2
    dx=(x+0.5-cx)/S; dy=(y+0.5-cy)/S; r=np.hypot(dx,dy); th=np.arctan2(dy,dx)
    ro,ri=(0.44,0.355) if not simple else (0.45,0.34)
    # halo behind everything
    halo=np.clip(1-r/0.47,0,1)**1.6
    img=over(img,to_img(np.ones((S,S,3))*lin('#5a2fb0'),halo*0.55))
    img=over(img,to_img(np.ones((S,S,3))*lin('#36e0ff'),np.clip(1-r/0.30,0,1)**2*0.55))
    if ring:
        inr=(r>=ri)&(r<=ro); t=(r-ri)/(ro-ri)
        nr=np.cos(np.pi*t)  # +1 inner edge faces inward... profile
        L=np.array([-0.55,-0.75]); L/=np.linalg.norm(L)
        rd=np.dstack([dx/np.maximum(r,1e-6),dy/np.maximum(r,1e-6)])
        ndl=-(nr)*(rd[...,0]*L[0]+rd[...,1]*L[1])
        shade=np.clip(0.30+0.62*ndl+0.12*np.sin(t*np.pi),0,1)**1.3
        dark=lin('#0b0b10'); light=lin('#8a90a3')
        rgb=dark[None,None,:]*(1-shade[...,None])+light[None,None,:]*shade[...,None]
        # brushed noise
        nz=np.asarray(Image.effect_noise((S,S),40).filter(ImageFilter.GaussianBlur(1.2)),float)/255-0.5
        rgb=rgb+nz[...,None]*0.06
        a=inr.astype(float)
        aa=np.clip(np.minimum((r-ri)*S/1.5,(ro-r)*S/1.5),0,1); a=a*aa
        img=over(img,to_img(rgb,a))
        # gold rims
        for rr,w in ((ro,0.012),(ri,0.010),(ri+(ro-ri)*0.5,0.0)):
            if w==0: continue
            band=np.clip(1-np.abs(r-rr)/w,0,1)
            gs=0.5+0.5*(-(rd[...,0]*L[0]+rd[...,1]*L[1]))*np.sign(rr-ri-0.001+0.0001)
            g=lin('#5a3a12')[None,None,:]*(1-gs[...,None])+lin('#ffe39a')[None,None,:]*gs[...,None]
            img=over(img,to_img(g,np.clip(band*2,0,1)))
        # engraved runes
        if not simple:
            rune=Image.new('L',(S,S),0); dr=ImageDraw.Draw(rune)
            n=18; rm=(ro+ri)/2*S; hgt=(ro-ri)*S*0.42
            for k in range(n):
                ang=k/n*2*math.pi+math.pi/n
                if any(abs(((ang-a0+math.pi)%(2*math.pi))-math.pi)<0.17 for a0 in (0,math.pi/2,math.pi,3*math.pi/2)): continue
                c=(cx+math.cos(ang)*rm, cy+math.sin(ang)*rm)
                tang=(-math.sin(ang),math.cos(ang)); nor=(math.cos(ang),math.sin(ang))
                def P(u,v): return (c[0]+tang[0]*u*hgt*0.55+nor[0]*v*hgt, c[1]+tang[1]*u*hgt*0.55+nor[1]*v*hgt)
                strokes=[[(0,-1),(0,1)]]
                kind=R.randrange(6)
                if kind==0: strokes+= [[(0,-0.4),(0.8,-1)],[(0,0.1),(0.8,-0.5)]]
                elif kind==1: strokes+= [[(0,-1),(0.8,-0.3),(0,0.3)]]
                elif kind==2: strokes+= [[(-0.8,-1),(0,-0.2),(0.8,-1)]]
                elif kind==3: strokes=[[(-0.6,-1),(-0.6,1)],[(0.6,-1),(0.6,1)],[(-0.6,-0.6),(0.6,0.2)]]
                elif kind==4: strokes+= [[(0,0.2),(-0.8,1)],[(0,0.2),(0.8,1)]]
                else: strokes=[[(-0.7,-1),(0.7,1)],[(0.7,-1),(-0.7,1)]]
                for st in strokes: dr.line([P(u,v) for u,v in st],fill=255,width=int(S*0.0075),joint='curve')
            img=over(img,glow(rune,'#3fe9ff',S*0.008,1.3))
            img=over(img,colorize(rune,np.ones((S,S,3))*lin('#c8fbff')))
        # studs
        for k in range(4):
            ang=k*math.pi/2-math.pi/2; rm=(ro+ri)/2
            c=(0.5+math.cos(ang)*rm,0.5+math.sin(ang)*rm); s=(ro-ri)*0.72
            tang=(-math.sin(ang),math.cos(ang)); nor=(math.cos(ang),math.sin(ang))
            pts=[(c[0]+nor[0]*s,c[1]+nor[1]*s),(c[0]+tang[0]*s*0.55,c[1]+tang[1]*s*0.55),(c[0]-nor[0]*s,c[1]-nor[1]*s),(c[0]-tang[0]*s*0.55,c[1]-tang[1]*s*0.55)]
            m=mask_poly(S,pts)
            img=over(img,glow(m,'#000000',S*0.004,0.8))
            img=over(img,colorize(m,grad_lin(S,'#fff0b5','#7a4e14',(c[0]-s,c[1]-s),(c[0]+s,c[1]+s))))
            # gem in stud
            g=Image.new('L',(S,S),0); gc=(c[0]*S,c[1]*S); gr=s*S*0.28
            ImageDraw.Draw(g).ellipse([gc[0]-gr,gc[1]-gr,gc[0]+gr,gc[1]+gr],fill=255)
            img=over(img,glow(g,'#ae6bff',S*0.006,1.2)); img=over(img,colorize(g,np.ones((S,S,3))*lin('#d9b8ff')))
    # crystal shards
    sc=1.0 if not simple else 1.12
    def T(p): return (0.5+(p[0]-0.5)*sc, 0.5+(p[1]-0.5)*sc)
    main=[T(p) for p in [(0.505,0.115),(0.6,0.33),(0.585,0.74),(0.5,0.885),(0.415,0.735),(0.405,0.35)]]
    left=[T(p) for p in [(0.30,0.47),(0.385,0.53),(0.40,0.74),(0.345,0.79),(0.305,0.66)]]
    right=[T(p) for p in [(0.70,0.43),(0.615,0.52),(0.605,0.72),(0.655,0.765),(0.695,0.62)]]
    crystal=Image.new('L',(S,S),0); dcr=ImageDraw.Draw(crystal)
    for poly in (main,left,right): dcr.polygon([(a*S,b*S) for a,b in poly],fill=255)
    img=over(img,glow(crystal,'#3fe9ff',S*0.05,0.9))
    img=over(img,glow(crystal,'#9b5cff',S*0.11,0.7))
    def facets(poly,ridge_top,ridge_bot,light_left=True):
        # split polygon into left/right halves along ridge, plus top bevel
        n=len(poly)
        out=[]
        cxp=sum(p[0] for p in poly)/n
        L=[p for p in poly if p[0]<=cxp+1e-6]; Rr=[p for p in poly if p[0]>=cxp-1e-6]
        return out
    def draw_shard(poly, top, bot, mid):
        # facets: left-upper, right-upper, left-lower, right-lower by connecting to ridge (top->mid->bot)
        pts=poly
        cols=[('#aaf9ff','#2fb8e8'),('#4fd2ff','#4a2fb0'),('#7fe9ff','#5b3fd0'),('#2a7fd8','#2a1470')]
        # build facet polygons using vertex ordering: top, right verts..., bot, left verts...
        i_top=pts.index(top); i_bot=pts.index(bot)
        n=len(pts)
        rightside=[]; i=i_top
        while i!=i_bot: rightside.append(pts[i]); i=(i+1)%n
        rightside.append(bot)
        leftside=[]; i=i_bot
        while i!=i_top: leftside.append(pts[i]); i=(i+1)%n
        leftside.append(top)
        f_right=rightside+[mid]; f_left=leftside+[mid]
        bb=(min(p[0] for p in pts),min(p[1] for p in pts),max(p[0] for p in pts),max(p[1] for p in pts))
        nonlocal_img=[None]
        layers=[]
        for poly2,(c0,c1),p0,p1 in ((f_left,('#c4fcff','#6d55f0'),(bb[0],bb[1]),(bb[2],bb[3])),(f_right,('#4fcfff','#4c16a8'),(bb[0],bb[1]),(bb[2],bb[3]))):
            m=mask_poly(S,poly2); layers.append(colorize(m,grad_lin(S,c0,c1,p0,p1)))
        # inner bright core along ridge
        core=Image.new('L',(S,S),0); ImageDraw.Draw(core).line([(top[0]*S,top[1]*S),(mid[0]*S,mid[1]*S),(bot[0]*S,bot[1]*S)],fill=255,width=int(S*0.006))
        return layers,core
    mmid=T((0.51,0.42))
    lay,core=draw_shard(main,main[0],main[3],mmid)
    for l in lay: img=over(img,l)
    l2,c2=draw_shard(left,left[0],left[3],T((0.36,0.6)))
    for l in l2: img=over(img,l)
    l3,c3=draw_shard(right,right[0],right[3],T((0.645,0.58)))
    for l in l3: img=over(img,l)
    # edge rim light (thin bright outline)
    edge=crystal.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))
    img=over(img,colorize(edge,np.ones((S,S,3))*lin('#e8feff')).filter(ImageFilter.GaussianBlur(0.8)))
    for c in (core,c2,c3):
        img=over(img,glow(c,'#d8ffff',S*0.004,0.9))
    # cracks of light
    cr=Image.new('L',(S,S),0); dc=ImageDraw.Draw(cr)
    def crack(p0,ang,length,depth=0):
        pts=[p0]; p=p0
        steps=7
        for i in range(steps):
            ang+=R.uniform(-0.5,0.5)
            p=(p[0]+math.cos(ang)*length/steps,p[1]+math.sin(ang)*length/steps); pts.append(p)
            if depth<1 and R.random()<0.3: crack(p,ang+R.choice([-1,1])*R.uniform(0.6,1.1),length*0.45,depth+1)
        dc.line([(a*S,b*S) for a,b in pts],fill=255,width=max(2,int(S*(0.0055 if depth==0 else 0.0035))),joint='curve')
    if not simple:
        crack(T((0.47,0.30)),1.25,0.30); crack(T((0.55,0.47)),2.0,0.24); crack(T((0.49,0.62)),0.9,0.22)
        crack(T((0.34,0.55)),1.3,0.16); crack(T((0.66,0.51)),1.9,0.16)
    else:
        crack(T((0.48,0.28)),1.3,0.36); crack(T((0.56,0.5)),2.1,0.22)
    cr=ImageChops.multiply(cr,crystal.filter(ImageFilter.MinFilter(5)))
    img=over(img,glow(cr,'#5ff3ff',S*0.012,1.4))
    img=over(img,glow(cr,'#c48bff',S*0.03,0.8))
    img=over(img,colorize(cr,np.ones((S,S,3))*lin('#ffffff')))
    # sparkles
    sp=Image.new('L',(S,S),0); ds=ImageDraw.Draw(sp)
    for (px,py,s) in ([(0.505,0.12,0.05),(0.62,0.33,0.025),(0.3,0.47,0.022),(0.7,0.43,0.02)] if not simple else [(0.505,0.12,0.06)]):
        px,py=T((px,py)); s*=S
        ds.polygon([(px*S,py*S-s),(px*S+s*0.16,py*S-s*0.16),(px*S+s,py*S),(px*S+s*0.16,py*S+s*0.16),(px*S,py*S+s),(px*S-s*0.16,py*S+s*0.16),(px*S-s,py*S),(px*S-s*0.16,py*S-s*0.16)],fill=255)
    img=over(img,glow(sp,'#bff8ff',S*0.008,1.5)); img=over(img,colorize(sp,np.ones((S,S,3))*lin('#ffffff')))
    return img

def bg(S, rounded=True, rad=0.18):
    y,x=np.mgrid[0:S,0:S]; r=np.hypot((x-S/2)/S,(y-S*0.46)/S)
    t=np.clip(r/0.72,0,1)[...,None]
    rgb=lin('#2b1856')*(1-t)+lin('#07060d')*t
    # faint vignette rays
    a=np.ones((S,S))
    im=to_img(rgb,a)
    if rounded:
        m=Image.new('L',(S,S),0); ImageDraw.Draw(m).rounded_rectangle([0,0,S-1,S-1],radius=int(S*rad),fill=255)
        im.putalpha(m)
    return im

def wordmark(text='ОСКОЛКИ ЭФИРА', H=300):
    ft=ImageFont.truetype('/workspace/logo/CormorantSC-Bold.ttf',H)
    l,t,r,b=ft.getbbox(text); pad=int(H*0.25)
    W,Hh=r-l+pad*2,b-t+pad*2
    m=Image.new('L',(W,Hh),0); ImageDraw.Draw(m).text((pad-l,pad-t),text,font=ft,fill=255)
    so=Image.new('L',(W,Hh),0); ImageDraw.Draw(so).text((pad-l,pad-t),text,font=ft,fill=255,stroke_width=int(H*0.045))
    img=Image.new('RGBA',(W,Hh),(0,0,0,0))
    # drop shadow + outer dark stroke
    sh=so.filter(ImageFilter.GaussianBlur(H*0.04)); img=over(img,to_img(np.zeros((Hh,W,3)),np.asarray(sh,float)/255*0.9))
    img=over(img,to_img(np.ones((Hh,W,3))*lin('#1a0d04'),np.asarray(so,float)/255))
    # gold gradient body
    yy=(np.mgrid[0:Hh,0:W][0]-pad)/(b-t)
    stops=[(0,'#fff6c9'),(0.38,'#f3c75a'),(0.52,'#b9771f'),(0.62,'#f0be55'),(1.0,'#7a4610')]
    def ramp(v):
        out=np.zeros(v.shape+(3,))
        for i in range(len(stops)-1):
            a0,c0=stops[i]; a1,c1=stops[i+1]
            k=np.clip((v-a0)/(a1-a0),0,1)[...,None]; sel=((v>=a0)&(v<=a1))[...,None] if i<len(stops)-2 else (v>=a0)[...,None]
            out=np.where(sel, lin(c0)*(1-k)+lin(c1)*k, out)
        return np.where((v<0)[...,None],lin(stops[0][1]),out)
    gold=ramp(yy)
    # bevel: emboss from blurred mask gradient
    mb=np.asarray(m.filter(ImageFilter.GaussianBlur(H*0.018)),float)/255
    gy,gx=np.gradient(mb)
    light=(-gx*0.6-gy*0.8)*H*0.09
    gold=gold*(1+np.clip(light,-0.5,0.8)[...,None])
    gold=gold+np.clip(light,0,1)[...,None]*0.25
    img=over(img,to_img(gold,np.asarray(m,float)/255))
    # inner thin highlight line
    return img

def full_logo():
    em=emblem(2048).resize((900,900),Image.LANCZOS)
    wm=wordmark(H=230)
    W=max(wm.width,1100); Hh=900+wm.height-120
    im=Image.new('RGBA',(W,Hh),(0,0,0,0))
    im.alpha_composite(em,((W-900)//2,0))
    im.alpha_composite(wm,((W-wm.width)//2,900-150))
    return im

if __name__=='__main__':
    em=emblem(2048); em.resize((1024,1024),Image.LANCZOS).save(OUT+'emblem_1024.png')
    sm=emblem(1024,simple=True); sm.save(OUT+'emblem_simple_1024.png')
    wm=wordmark(); wm.save(OUT+'wordmark.png')
    full_logo().save(OUT+'logo_full.png')
    print('ok')
