"""Ретаргет анимаций Universal Animation Library 1+2 (CC0, Quaternius) на скелеты персонажей.
Для каждого пола создаётся assets/characters/anims_{m,f}.gltf: скелет (как в human_*.gltf) + выбранные клипы.
Поворот кости переносится как отклонение от позы покоя в пространстве родителя: q_t = (q_s * inv(rest_s)) * rest_t.
Перемещение — только таз (масштаб по высоте таза). Масштабы не переносятся."""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from gltfio import Gltf, Writer

HOME = os.path.expanduser('~/assets_dl')
UAL = [HOME + '/ual/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb',
       HOME + '/ual2/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb']
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'characters')
# имя в игре : имя в библиотеке
CLIPS = {
    'idle': 'Idle_Loop', 'idle_sword': 'Sword_Idle', 'idle_shield': 'Idle_Shield_Loop', 'idle_spell': 'Spell_Simple_Idle_Loop',
    'idle_fold': 'Idle_FoldArms_Loop', 'walk': 'Walk_Loop', 'run': 'Jog_Fwd_Loop', 'sprint': 'Sprint_Loop',
    'jump_start': 'Jump_Start', 'jump_air': 'Jump_Loop', 'jump_land': 'Jump_Land',
    'attack_a': 'Sword_Regular_A', 'attack_b': 'Sword_Regular_B', 'attack_c': 'Sword_Regular_C',
    'attack_heavy': 'Sword_Heavy_Combo', 'attack_combo': 'Sword_Regular_Combo', 'sword_attack': 'Sword_Attack',
    'dash': 'Sword_Dash', 'roll': 'Roll', 'block': 'Sword_Block', 'shield_bash': 'Shield_OneShot',
    'cast': 'Spell_Simple_Shoot', 'cast_enter': 'Spell_Simple_Enter', 'bow_aim': 'Pistol_Aim_Neutral', 'bow_shoot': 'Pistol_Shoot',
    'throw': 'OverhandThrow', 'punch_a': 'Punch_Jab', 'punch_b': 'Punch_Cross', 'hook': 'Melee_Hook',
    'hit': 'Hit_Chest', 'hit_head': 'Hit_Head', 'knockback': 'Hit_Knockback', 'death': 'Death01',
    'consume': 'Consume', 'interact': 'Interact', 'cheer': 'Yes', 'dance': 'Dance_Loop',
    'zombie_walk': 'Zombie_Walk_Fwd_Loop', 'zombie_attack': 'Zombie_Scratch', 'zombie_idle': 'Zombie_Idle_Loop',
}

def qmul(a, b):
    ax, ay, az, aw = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    bx, by, bz, bw = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return np.stack([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz], -1)
def qinv(a): return a * np.array([-1, -1, -1, 1], np.float32)

def build(gl):
    char = Gltf(os.path.join(OUT, f'human_{gl}.gltf'))
    W = Writer()
    # скелет без мешей
    for n in char.j['nodes']:
        if 'mesh' in n: continue
        W.j['nodes'].append({k: v for k, v in n.items() if k in ('name', 'translation', 'rotation', 'scale', 'children')})
    valid = len(W.j['nodes'])
    for n in W.j['nodes']:
        if 'children' in n:
            n['children'] = [c for c in n['children'] if c < valid]
            if not n['children']: del n['children']
    W.j['scenes'][0]['nodes'] = [i for i, n in enumerate(W.j['nodes']) if n['name'] == 'Armature']
    tidx = {n['name']: i for i, n in enumerate(W.j['nodes'])}
    # крошечный скин-меш, чтобы импортёр Godot собрал Skeleton3D (иначе кости станут обычными узлами)
    sk = char.j['skins'][0]
    joints = [tidx[char.j['nodes'][i]['name']] for i in sk['joints']]
    ibm = char.acc(sk['inverseBindMatrices']).astype(np.float32).reshape(-1, 16)
    W.j['skins'].append({'joints': joints, 'inverseBindMatrices': W.add(ibm, typ='MAT4'), 'skeleton': tidx['root']})
    tri = np.array([[0, 0, 0], [0.01, 0, 0], [0, 0.01, 0]], np.float32)
    attrs = {'POSITION': W.add(tri, 34962, minmax=True), 'JOINTS_0': W.add(np.zeros((3, 4), np.uint16), 34962),
             'WEIGHTS_0': W.add(np.array([[1, 0, 0, 0]] * 3, np.float32), 34962)}
    W.j['meshes'].append({'name': 'Dummy', 'primitives': [{'attributes': attrs}]})
    W.j['nodes'].append({'name': 'Dummy', 'mesh': 0, 'skin': 0})
    W.j['nodes'][tidx['Armature']].setdefault('children', []).append(len(W.j['nodes']) - 1)
    trest = {n['name']: np.array(n.get('rotation', [0, 0, 0, 1]), np.float32) for n in W.j['nodes']}
    tpel = np.array(W.j['nodes'][tidx['pelvis']]['translation'], np.float32)
    count = 0
    for path in UAL:
        src = Gltf(path)
        snodes = src.j['nodes']
        srest = {n.get('name'): np.array(n.get('rotation', [0, 0, 0, 1]), np.float32) for n in snodes}
        spel = np.array([n for n in snodes if n.get('name') == 'pelvis'][0]['translation'], np.float32)
        ratio = tpel[2] / spel[2]
        byname = {a['name']: a for a in src.j['animations']}
        for game_name, lib_name in CLIPS.items():
            if lib_name not in byname: continue
            a = byname[lib_name]
            anim = {'name': game_name, 'channels': [], 'samplers': []}
            for ch in a['channels']:
                bone = snodes[ch['target']['node']].get('name')
                path_ = ch['target']['path']
                if bone not in tidx or bone in ('root',): continue
                if path_ == 'scale': continue
                if path_ == 'translation' and bone != 'pelvis': continue
                s = a['samplers'][ch['sampler']]
                t = src.acc(s['input']).astype(np.float32).reshape(-1)
                v = src.acc(s['output']).astype(np.float32)
                if path_ == 'rotation':
                    v = qmul(qmul(v, qinv(srest[bone])[None]), trest[bone][None])
                    v /= np.linalg.norm(v, axis=1, keepdims=True)
                    # убираем «перескоки» знака кватерниона
                    for k in range(1, len(v)):
                        if np.dot(v[k], v[k - 1]) < 0: v[k] = -v[k]
                else:
                    v = tpel + (v - spel) * ratio
                    v[:, 0] = tpel[0] + (v[:, 0] - tpel[0])
                ti = W.add(t - t[0], minmax=True)
                vi = W.add(v.astype(np.float32))
                anim['samplers'].append({'input': ti, 'output': vi, 'interpolation': s.get('interpolation', 'LINEAR')})
                anim['channels'].append({'sampler': len(anim['samplers']) - 1, 'target': {'node': tidx[bone], 'path': path_}})
            W.j.setdefault('animations', []).append(anim); count += 1
    p = os.path.join(OUT, f'anims_{gl}.gltf')
    W.save(p)
    print(gl, 'clips', count, os.path.getsize(p.replace('.gltf', '.bin')) // 1024, 'KB')

if __name__ == '__main__':
    for gl in ('m', 'f'): build(gl)
