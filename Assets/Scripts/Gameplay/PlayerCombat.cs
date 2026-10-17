using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    /// <summary>Атаки и умения игрока. Слоты: 0 — базовая атака, 1-2 — умения класса, 3 — умение пути (после превращения).</summary>
    public class PlayerCombat : MonoBehaviour
    {
        PlayerCharacter pc;
        PlayerController ctrl;
        public readonly float[] cooldowns = new float[4];
        float attackTimer;
        ClassDef cls;

        void Awake() { pc = GetComponent<PlayerCharacter>(); ctrl = GetComponent<PlayerController>(); }
        void Start() { cls = ClassDefs.Get(pc.Data.classId); }

        public SkillDef GetSkill(int slot)
        {
            if (slot < 3) return cls.skills[slot];
            return AscendancyDefs.Get(pc.Data.ascendancy)?.skill;
        }

        public bool IsUnlocked(int slot, out string reason)
        {
            reason = null;
            if (slot < 3)
            {
                int need = cls.skillUnlockClassLevel[slot];
                if (pc.Data.classLevel < need) { reason = "мастер.\n" + need; return false; }
                return true;
            }
            if (GetSkill(3) == null) { reason = "путь"; return false; }
            return true;
        }

        public float MaxCooldown(int slot)
        {
            var s = GetSkill(slot);
            if (s == null) return 0;
            if (slot == 0) return cls.attackInterval / (pc.Stats.AttackSpeed * (pc.rageTimer > 0 ? 1.5f : 1f));
            return s.cooldown * (1 - pc.Stats.Cdr);
        }

        void Update()
        {
            for (int i = 0; i < 4; i++) if (cooldowns[i] > 0) cooldowns[i] -= Time.deltaTime;
            if (pc.Dead) return;
            var hud = HUD.Instance;
            bool attackHeld = hud != null && hud.AttackHeld;
#if UNITY_EDITOR || UNITY_STANDALONE
            attackHeld |= Input.GetKey(KeyCode.J) || Input.GetKey(KeyCode.Space);
            if (Input.GetKeyDown(KeyCode.Alpha1)) TryUse(1);
            if (Input.GetKeyDown(KeyCode.Alpha2)) TryUse(2);
            if (Input.GetKeyDown(KeyCode.Alpha3)) TryUse(3);
            if (Input.GetKeyDown(KeyCode.Q)) UsePotion();
#endif
            if (attackHeld) TryUse(0);
        }

        public void UsePotion()
        {
            if (pc.Dead) return;
            if (pc.Data.potions <= 0) { Toast.Show("Нет зелий"); return; }
            if (pc.Hp >= pc.Stats.MaxHp - 1) { Toast.Show("Здоровье полное"); return; }
            pc.Data.potions--;
            pc.Heal(pc.Stats.MaxHp * 0.45f);
            FX.Burst(transform.position + Vector3.up, 1.5f, new Color(1f, 0.2f, 0.3f), 0.5f);
        }

        public bool TryUse(int slot)
        {
            if (pc.Dead || cooldowns[slot] > 0) return false;
            if (!IsUnlocked(slot, out var reason))
            {
                if (slot > 0) Toast.Show(slot == 3 ? "Умение пути откроется после превращения (дерево талантов)" : $"Нужно мастерство класса {cls.skillUnlockClassLevel[slot]}");
                return false;
            }
            var s = GetSkill(slot);
            if (pc.Mp < s.manaCost) { Toast.Show("Не хватает маны", 1f); return false; }
            pc.Mp -= s.manaCost;
            cooldowns[slot] = MaxCooldown(slot);
            Execute(s);
            return true;
        }

        Enemy FindTarget(float range)
        {
            Enemy best = null; float bestScore = float.MaxValue;
            var p = transform.position; var f = transform.forward;
            foreach (var e in Enemy.All)
            {
                if (!e.Alive) continue;
                var d = e.transform.position - p; d.y = 0;
                float dist = d.magnitude;
                if (dist > range) continue;
                float score = dist * (1.5f - Vector3.Dot(f, d.normalized) * 0.5f);
                if (score < bestScore) { bestScore = score; best = e; }
            }
            return best;
        }

        public float RollDamage(float mult, bool spell, out bool crit)
        {
            var st = pc.Stats;
            float dmg = st.Damage * st.DamageMult * mult * pc.RageMult * Random.Range(0.9f, 1.1f);
            if (spell || cls.spellBased) dmg *= st.SpellMult;
            crit = Random.value < st.Crit;
            if (crit) dmg *= st.CritMult;
            return dmg;
        }

        public void Hit(Enemy e, float mult, bool spell = false, bool forceCrit = false)
        {
            if (e == null || !e.Alive) return;
            float dmg = RollDamage(mult, spell, out bool crit);
            if (forceCrit && !crit) { dmg *= pc.Stats.CritMult; crit = true; }
            e.TakeDamage(dmg, crit, transform.position);
            if (pc.Stats.Leech > 0) pc.Heal(dmg * pc.Stats.Leech);
        }

        void HitArea(Vector3 center, float radius, float mult, bool spell, System.Action<Enemy> extra = null)
        {
            var list = new List<Enemy>(Enemy.All);
            foreach (var e in list)
            {
                if (!e.Alive) continue;
                var d = e.transform.position - center; d.y = 0;
                if (d.magnitude <= radius + e.Radius) { Hit(e, mult, spell); extra?.Invoke(e); }
            }
        }

        void Execute(SkillDef s)
        {
            var target = FindTarget(Mathf.Max(s.range, cls.attackRange) + 2);
            if (target != null && s.kind != SkillKind.Dash) ctrl.FaceTowards(target.transform.position);
            pc.Visual.PlayAttack();
            var origin = transform.position + Vector3.up * 1.3f + transform.forward * 0.6f;
            switch (s.kind)
            {
                case SkillKind.MeleeSwing:
                {
                    var center = transform.position + transform.forward * 1.2f;
                    var list = new List<Enemy>(Enemy.All);
                    foreach (var e in list)
                    {
                        if (!e.Alive) continue;
                        var d = e.transform.position - transform.position; d.y = 0;
                        if (d.magnitude <= cls.attackRange + e.Radius && Vector3.Angle(transform.forward, d) < 70) Hit(e, 1f);
                    }
                    FX.Burst(center + Vector3.up, 1.3f, new Color(1, 1, 1), 0.15f);
                    break;
                }
                case SkillKind.Projectile:
                    Projectile.Fire(origin, Dir(origin, target), 22f, s.range, s.color, 0.25f, true, e => Hit(e, 1f));
                    break;
                case SkillKind.Spin:
                    HitArea(transform.position, s.radius, s.damageMult, false);
                    FX.Ring(transform.position, s.radius, s.color, 0.35f);
                    break;
                case SkillKind.Dash:
                {
                    var dir = target != null ? (target.transform.position - transform.position) : transform.forward; dir.y = 0;
                    ctrl.FaceTowards(transform.position + dir);
                    ctrl.Dash(dir, s.range, 0.22f);
                    var start = transform.position; var end = start + dir.normalized * s.range;
                    var list = new List<Enemy>(Enemy.All);
                    foreach (var e in list)
                        if (e.Alive && DistToSegment(e.transform.position, start, end) < s.radius + e.Radius) Hit(e, s.damageMult);
                    FX.Burst(end + Vector3.up, 2f, s.color, 0.3f);
                    break;
                }
                case SkillKind.Volley:
                {
                    var baseDir = Dir(origin, target);
                    for (int i = -2; i <= 2; i++)
                        Projectile.Fire(origin, Quaternion.Euler(0, i * 12, 0) * baseDir, 22f, s.range, s.color, 0.22f, true, e => Hit(e, s.damageMult));
                    break;
                }
                case SkillKind.ArrowRain:
                {
                    var pos = target != null ? target.transform.position : transform.position + transform.forward * 8;
                    FX.Ring(pos, s.radius, s.color, 0.6f);
                    StartCoroutine(Delayed(0.4f, () => { HitArea(pos, s.radius, s.damageMult, false); FX.Burst(pos + Vector3.up, s.radius, s.color, 0.3f); }));
                    break;
                }
                case SkillKind.Fireball:
                    Projectile.Fire(origin, Dir(origin, target), 16f, s.range, s.color, 0.5f, true, e =>
                    {
                        HitArea(e.transform.position, s.radius, s.damageMult, true);
                        FX.Burst(e.transform.position + Vector3.up, s.radius, s.color, 0.4f);
                    });
                    break;
                case SkillKind.FrostNova:
                    HitArea(transform.position, s.radius, s.damageMult, true, e => e.Slow(0.4f, 3f));
                    FX.Ring(transform.position, s.radius, s.color, 0.45f);
                    break;
                case SkillKind.Rage:
                    pc.rageTimer = 8f;
                    FX.Burst(transform.position + Vector3.up, 3f, s.color, 0.6f);
                    Toast.Show("ЯРОСТЬ!", 1.2f);
                    break;
                case SkillKind.HolyShield:
                    pc.shieldTimer = 6f; pc.Heal(pc.Stats.MaxHp * 0.35f);
                    FX.Burst(transform.position + Vector3.up, 2.5f, s.color, 0.8f);
                    break;
                case SkillKind.ShadowStrike:
                    if (target == null) { Toast.Show("Нет цели", 1f); cooldowns[3] = 0.5f; break; }
                    var behind = target.transform.position - target.transform.forward * 1.3f; behind.y = transform.position.y;
                    FX.Burst(transform.position + Vector3.up, 1.5f, s.color, 0.3f);
                    ctrl.Teleport(behind); ctrl.FaceTowards(target.transform.position);
                    Hit(target, s.damageMult, false, true);
                    FX.Burst(target.transform.position + Vector3.up, 1.5f, s.color, 0.3f);
                    break;
                case SkillKind.Meteor:
                {
                    var pos = target != null ? target.transform.position : transform.position + transform.forward * 8;
                    FX.Telegraph(pos, s.radius, 0.9f);
                    StartCoroutine(Delayed(0.9f, () => { HitArea(pos, s.radius, s.damageMult, true); FX.Burst(pos + Vector3.up, s.radius, s.color, 0.6f); }));
                    break;
                }
                case SkillKind.Summon:
                    for (int i = 0; i < 2; i++)
                        Minion.Spawn(transform.position + transform.right * (i == 0 ? -1.5f : 1.5f), this, s.damageMult, 25f);
                    break;
                case SkillKind.BeastRoar:
                    HitArea(transform.position, s.radius, s.damageMult, false, e => e.Stun(2f));
                    pc.Heal(pc.Stats.MaxHp * 0.15f);
                    FX.Ring(transform.position, s.radius, s.color, 0.5f);
                    break;
            }
        }

        Vector3 Dir(Vector3 origin, Enemy target)
        {
            if (target == null) return transform.forward;
            var d = target.transform.position + Vector3.up * 0.8f - origin; d.y = 0;
            return d.normalized;
        }

        static float DistToSegment(Vector3 p, Vector3 a, Vector3 b)
        {
            p.y = a.y = b.y = 0;
            var ab = b - a; float t = Mathf.Clamp01(Vector3.Dot(p - a, ab) / Mathf.Max(ab.sqrMagnitude, 0.001f));
            return Vector3.Distance(p, a + ab * t);
        }

        System.Collections.IEnumerator Delayed(float t, System.Action a)
        {
            yield return new WaitForSeconds(t);
            a();
        }
    }
}
