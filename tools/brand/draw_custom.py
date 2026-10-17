# Hand-made 32x32 pixel icons in the Idylwild palette (belt, circlet, wizard hat) — original work for the game.
from PIL import Image
import math
W=32
OUT='/workspace/icons_src/custom/'
def hexc(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))+(255,)
BLACK=(0,0,0,255)
RAMPS={
 'leather':['#261711','#4d291a','#7c4b26','#ae754f'],
 'darkleather':['#1a1414','#2f2426','#4a3a3c','#6e5a5a'],
 'redleather':['#2a0f0f','#5a1d1a','#8a3226','#b65a3e'],
 'iron':['#27262b','#555664','#8f95a3','#b5bec6'],
 'silver':['#555664','#8f95a3','#b5bec6','#e7f0f4'],
 'gold':['#423727','#665a19','#99882a','#c6bc5f'],
 'bronze':['#3a2414','#6b4223','#9a6634','#c99459'],
 'brownfelt':['#261711','#4d291a','#7c4b26','#9c6a43'],
 'bluefelt':['#0e1a2e','#173a4f','#386f8c','#4f8bb0'],
 'purplefelt':['#1c1030','#3a2160','#5d3a8f','#8460b8'],
 'ruby':['#3a0a0a','#7a1515','#c03030','#f08080'],
 'emerald':['#1d3010','#4f7825','#8db724','#abe567'],
 'sapphire':['#0b1d33','#173a4f','#386f8c','#9fd0f0'],
 'amethyst':['#24103a','#4b2380','#7d4ac0','#c8a0f0'],
}
class Canvas:
    def __init__(s): s.px=[[None]*W for _ in range(W)]
    def put(s,x,y,c):
        if 0<=x<W and 0<=y<W: s.px[y][x]=c
    def shade(s,mask,ramp,light=(-0.6,-0.8),bias=0.0):
        # mask: set of (x,y); shade by normal-ish: distance to edges + light direction
        r=[hexc(h) for h in RAMPS[ramp]]
        xs=[p[0] for p in mask]; ys=[p[1] for p in mask]
        for (x,y) in mask:
            # local gradient: count neighbours toward light
            up=(x+round(light[0]*1.5),y+round(light[1]*1.5)) in mask
            dn=(x-round(light[0]*1.5),y-round(light[1]*1.5)) in mask
            lvl=2
            if not up: lvl=3
            elif not dn: lvl=0 if not ((x-1,y+1) in mask and (x+1,y+1) in mask) else 1
            lvl=max(0,min(3,lvl+bias))
            s.put(x,y,r[int(lvl)])
    def outline(s):
        add=[]
        for y in range(W):
            for x in range(W):
                if s.px[y][x] is None:
                    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                        xx,yy=x+dx,y+dy
                        if 0<=xx<W and 0<=yy<W and s.px[yy][xx] is not None and s.px[yy][xx]!=BLACK: add.append((x,y)); break
        for x,y in add: s.px[y][x]=BLACK
    def save(s,name):
        im=Image.new('RGBA',(W,W),(0,0,0,0))
        for y in range(W):
            for x in range(W):
                if s.px[y][x]: im.putpixel((x,y),s.px[y][x])
        im.save(OUT+name+'.png')

def ellipse_ring(cx,cy,rx,ry,th):
    m=set()
    for y in range(W):
        for x in range(W):
            d=((x+0.5-cx)/rx)**2+((y+0.5-cy)/ry)**2
            d2=((x+0.5-cx)/(rx-th))**2+((y+0.5-cy)/(ry-th*0.7))**2
            if d<=1.0 and d2>1.0: m.add((x,y))
    return m
def rect(x0,y0,x1,y1): return {(x,y) for x in range(x0,x1+1) for y in range(y0,y1+1)}
def disc(cx,cy,r): return {(x,y) for x in range(W) for y in range(W) if (x+0.5-cx)**2+(y+0.5-cy)**2<=r*r}

def gem(c,cx,cy,r,kind):
    m=disc(cx,cy,r); c.shade(m,kind,bias=0)
    rr=[hexc(h) for h in RAMPS[kind]]
    c.put(int(cx-r*0.4),int(cy-r*0.4),hexc('#ffffff'))

def belt(name,leather,metal,studs=None,plates=False,gemk=None):
    c=Canvas()
    band=ellipse_ring(16,17,14.5,9.5,4.2)
    c.shade(band,leather)
    # stitching on the front strap
    r=[hexc(h) for h in RAMPS[leather]]
    for x in range(5,28,2):
        y=None
        for yy in range(31,0,-1):
            if (x,yy) in band: y=yy; break
        if y and (x,y-2) in band: c.put(x,y-2,r[3])
    if studs:
        for a in range(0,360,40):
            x=int(16+12.3*math.cos(math.radians(a))); y=int(17+7.8*math.sin(math.radians(a)))
            if (x,y) in band: c.put(x,y,hexc(RAMPS[studs][3])); c.put(x+1,y+1,hexc(RAMPS[studs][1]))
    if plates:
        for px in (6,24):
            pm=rect(px-1,20,px+2,24)&band|rect(px-1,21,px+2,24)
            c.shade(pm,metal)
    # buckle
    bk=rect(12,21,20,29)-rect(14,23,18,27)
    c.shade(bk,metal)
    tongue=rect(16,23,16,27)
    c.shade(tongue,metal,bias=1)
    # strap through buckle
    c.shade(rect(14,23,15,27)|rect(17,23,18,27),leather,bias=-1)
    if gemk: gem(c,16,10.5,2.2,gemk)
    c.outline(); c.save(name)

def circlet(name,metal,gems):
    c=Canvas()
    band=ellipse_ring(16,18,14,8.5,3.4)
    c.shade(band,metal)
    # front crest
    crest=rect(13,22,19,25)|rect(14,20,18,22)|{(16,19)}
    c.shade(crest,metal,bias=1)
    for i,(gx,gy,gk,gr) in enumerate(gems):
        gem(c,gx,gy,gr,gk)
    c.outline(); c.save(name)

def hat(name,felt,bandk=None,stars=None,tip_bend=1):
    c=Canvas()
    brim=set()
    for y in range(W):
        for x in range(W):
            if ((x+0.5-16)/15)**2+((y+0.5-25)/4.6)**2<=1: brim.add((x,y))
    cone=set()
    for y in range(4,25):
        t=(y-4)/20.0
        half=1+t*7.5
        off=(1-t)**2*7*tip_bend
        cx=16+off
        for x in range(W):
            if abs(x+0.5-cx)<=half: cone.add((x,y))
    c.shade(brim,felt,bias=-1)
    c.shade(cone,felt)
    if bandk:
        b=set(p for p in cone if 19<=p[1]<=21)
        c.shade(b,bandk,bias=0)
        if stars is None: gem(c,16,20,1.6,'sapphire' if felt!='bluefelt' else 'ruby')
    if stars:
        for (sx,sy) in stars:
            col=hexc(RAMPS['gold'][3]); hi=hexc('#fff6c8')
            for dx,dy in ((0,0),(1,0),(-1,0),(0,1),(0,-1)): c.put(sx+dx,sy+dy,col)
            c.put(sx,sy,hi)
    c.outline(); c.save(name)

belt('belt_t0','leather','iron')
belt('belt_t1','darkleather','silver',studs='silver')
belt('belt_t2','redleather','gold',studs='gold',plates=True,gemk='ruby')
circlet('circlet_t0','bronze',[(16,22.5,'emerald',2.2)])
circlet('circlet_t1','silver',[(16,22.5,'sapphire',2.5)])
circlet('circlet_t2','gold',[(16,22.5,'amethyst',2.8),(6,21,'sapphire',1.7),(26,21,'sapphire',1.7)])
hat('hat_t0','brownfelt')
hat('hat_t1','bluefelt',bandk='gold')
hat('hat_t2','purplefelt',bandk='gold',stars=[(17,12),(20,16),(14,17)])
print('ok')
