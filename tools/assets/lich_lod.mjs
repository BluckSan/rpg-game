// v0.9.5: LOD Кел'Таар из GLB Pigcraft (CC BY 4.0). npm i @gltf-transform/core @gltf-transform/functions meshoptimizer sharp
// Подготовка: gltf-transform dedup→flatten→join→weld исходника, затем: node lich_lod.mjs in.glb keltaar.glb keltaar_lo.glb
import { NodeIO, Document } from '@gltf-transform/core';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
const [,, inp, outPc, outPh] = process.argv;
const io = new NodeIO(); const doc = await io.read(inp);
const prim = doc.getRoot().listMeshes()[0].listPrimitives()[0];
const P = prim.getAttribute('POSITION').getArray(), UV = prim.getAttribute('TEXCOORD_0').getArray(), I = prim.getIndices().getArray();
const mat = prim.getMaterial(); const img = mat.getBaseColorTexture().getImage();
const { data, info } = await sharp(Buffer.from(img)).raw().toBuffer({ resolveWithObject: true });
const W = info.width, H = info.height, C = info.channels;
// weld by position
const key = new Map(), remap = new Uint32Array(P.length/3); let nv = 0; const pos = [], col = [], cnt = [];
for (let v = 0; v < P.length/3; v++) {
  const k = `${Math.round(P[3*v]*2e4)},${Math.round(P[3*v+1]*2e4)},${Math.round(P[3*v+2]*2e4)}`;
  let id = key.get(k); if (id === undefined) { id = nv++; key.set(k, id); pos.push(P[3*v],P[3*v+1],P[3*v+2]); col.push(0,0,0); cnt.push(0); }
  remap[v] = id;
  const u = UV[2*v] - Math.floor(UV[2*v]), w = UV[2*v+1] - Math.floor(UV[2*v+1]);
  const x = Math.min(W-1, Math.floor(u*W)), y = Math.min(H-1, Math.floor(w*H)), o = (y*W+x)*C;
  for (let c = 0; c < 3; c++) col[3*id+c] += data[o+c]/255; cnt[id]++;
}
for (let i=0;i<pos.length;i+=3){ const y=pos[i+1], z=pos[i+2]; pos[i+1]=z; pos[i+2]=-y; const x=pos[i]; pos[i]=-pos[i+2]; pos[i+2]=x; }  // Z-up -> Y-up
const pf = new Float32Array(pos), cf = new Float32Array(nv*3);
for (let i = 0; i < nv; i++) for (let c = 0; c < 3; c++) cf[3*i+c] = Math.pow(col[3*i+c]/cnt[i], 2.2);  // sRGB -> linear
const idx = new Uint32Array(I.length); for (let i = 0; i < I.length; i++) idx[i] = remap[I[i]];
console.log('welded verts', nv, 'tris', idx.length/3);
await MeshoptSimplifier.ready;
function build(target, out) {
  const [ri, err] = MeshoptSimplifier.simplifyWithAttributes(idx, pf, 3, cf, 3, [0.5,0.5,0.5], null, target*3, 0.08, ['LockBorder'].slice(1));
  // compact
  const m = new Map(); const np = [], nc = [], ni = new Uint32Array(ri.length);
  for (let i = 0; i < ri.length; i++) { let v = ri[i], id = m.get(v); if (id === undefined) { id = m.size; m.set(v, id); np.push(pf[3*v],pf[3*v+1],pf[3*v+2]); nc.push(cf[3*v],cf[3*v+1],cf[3*v+2],1); } ni[i] = id; }
  // smooth normals
  const nn = new Float32Array(np.length);
  for (let t = 0; t < ni.length; t += 3) { const [a,b,c] = [ni[t],ni[t+1],ni[t+2]];
    const ux=np[3*b]-np[3*a],uy=np[3*b+1]-np[3*a+1],uz=np[3*b+2]-np[3*a+2],vx=np[3*c]-np[3*a],vy=np[3*c+1]-np[3*a+1],vz=np[3*c+2]-np[3*a+2];
    const nx=uy*vz-uz*vy, ny=uz*vx-ux*vz, nz=ux*vy-uy*vx; for (const k of [a,b,c]) { nn[3*k]+=nx; nn[3*k+1]+=ny; nn[3*k+2]+=nz; } }
  for (let i = 0; i < nn.length; i += 3) { const l = Math.hypot(nn[i],nn[i+1],nn[i+2])||1; nn[i]/=l; nn[i+1]/=l; nn[i+2]/=l; }
  // pivot: feet at origin, centered xz
  let mn=[1e9,1e9,1e9], mx=[-1e9,-1e9,-1e9]; for (let i=0;i<np.length;i+=3) for (let c=0;c<3;c++){mn[c]=Math.min(mn[c],np[i+c]);mx[c]=Math.max(mx[c],np[i+c]);}
  const h = mx[1]-mn[1]; for (let i=0;i<np.length;i+=3){ np[i]=(np[i]-(mn[0]+mx[0])/2)/h; np[i+1]=(np[i+1]-mn[1])/h; np[i+2]=(np[i+2]-(mn[2]+mx[2])/2)/h; }
  const d = new Document(); const buf = d.createBuffer();
  const acc = (arr, type) => d.createAccessor().setArray(arr).setType(type).setBuffer(buf);
  const mt = d.createMaterial('lich').setRoughnessFactor(0.75).setMetallicFactor(0.05).setDoubleSided(true);
  const p = d.createPrimitive().setAttribute('POSITION', acc(new Float32Array(np),'VEC3')).setAttribute('NORMAL', acc(nn,'VEC3'))
    .setAttribute('COLOR_0', acc(new Float32Array(nc),'VEC4')).setIndices(acc(np.length/3 > 65535 ? ni : new Uint16Array(ni),'SCALAR')).setMaterial(mt);
  const mesh = d.createMesh('keltaar').addPrimitive(p);
  const node = d.createNode('Keltaar').setMesh(mesh); d.createScene().addChild(node);
  d.getRoot().getAsset().extras = { title: 'Skeletal Lich King in Bone Crown and Robes', author: 'Pigcraft (@s8819296)', license: 'CC-BY-4.0', note: 'decimated, vertex-colored for Нори' };
  console.log(out, 'tris', ni.length/3, 'verts', np.length/3, 'ext', (mx[0]-mn[0]).toFixed(3), h.toFixed(3), (mx[2]-mn[2]).toFixed(3), 'err', err);
  return io.write(out, d);
}
await build(16000, outPc); await build(5000, outPh);
