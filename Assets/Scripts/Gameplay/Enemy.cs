using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    public enum EnemyKind { Slime, Wolf, SkeletonArcher, Goblin, TrollBoss, Skeleton }

    public class EnemyDef
    {
        public EnemyKind kind;
        public string name;
        public float hp, damage, speed, attackRange, attackInterval, aggroRange, radius, xp;
        public bool ranged, boss;
        public Color color;

        public static readonly Dictionary<EnemyKind, EnemyDef> All = new Dictionary<EnemyKind, EnemyDef>
        {
            { EnemyKind.Slime, new EnemyDef { kind = EnemyKind.Slime, name = "Слизень", hp = 40, damage = 6, speed = 2.2f, attackRange = 1.6f, attackInterval = 1.4f, aggroRange = 8, radius = 0.6f, xp = 14, color = new Color(0.4f,0.85f,0.3f) } },
            { EnemyKind.Wolf, new EnemyDef { kind = EnemyKind.Wolf, name = "Серый волк", hp = 55, damage = 9, speed = 5.2f, attackRange = 1.8f, attackInterval = 1.0f, aggroRange = 11, radius = 0.7f, xp = 22, color = new Color(0.45f,0.45f,0.48f) } },
            { EnemyKind.SkeletonArcher, new EnemyDef { kind = EnemyKind.SkeletonArcher, name = "Скелет-лучник", hp = 50, damage = 11, speed = 2.6f, attackRange = 11f, attackInterval = 1.8f, aggroRange = 13, radius = 0.5f, xp = 28, ranged = true, color = new Color(0.9f,0.88f,0.8f) } },
            { EnemyKind.Goblin, new EnemyDef { kind = EnemyKind.Goblin, name = "Гоблин-громила", hp = 120, damage = 18, speed = 3f, attackRange = 2.2f, attackInterval = 1.6f, aggroRange = 10, radius = 0.8f, xp = 45, color = new Color(0.35f,0.55f,0.2f) } },
            { EnemyKind.TrollBoss, new EnemyDef { kind = EnemyKind.TrollBoss, name = "Древний тролль", hp = 900, damage = 30, speed = 3.2f, attackRange = 3.2f, attackInterval = 1.8f, aggroRange = 16, radius = 1.6f, xp = 500, boss = true, color = new Color(0.4f,0.5f,0.45f) } },
            { EnemyKind.Skeleton, new EnemyDef { kind = EnemyKind.Skeleton, name = "Скелет-воин", hp = 70, damage = 12, speed = 3.4f, attackRange = 1.9f, attackInterval = 1.2f, aggroRange = 11, radius = 0.5f, xp = 30, color = new Color(0.85f,0.83f,0.75f) } },
        };
    }

    /// <summary>Враг: блуждание у точки появления, погоня, атака, возврат (поводок), смерть с наградой.</summary>
    public class Enemy : MonoBehaviour
    {
        public static readonly List<Enemy> All = new List<Enemy>();

        public EnemyDef def;
        public int level;
        public float hp, maxHp;
        public bool Alive => hp > 0;
        public float Radius => def.radius;
        public string DisplayName => $"{def.name} ({level})";
        public System.Action<Enemy> onDeath;

        Vector3 home, wanderTarget;
        float attackTimer, wanderTimer, slowTimer, slowFactor = 1, stunTimer, bossSkillTimer = 5;
        bool aggro, returning;
        Transform model;
        float animPhase, hitFlash;
        Vector3 baseScale;
        public Transform Target; // игрок или миньон

        public static Enemy Spawn(EnemyKind kind, int level, Vector3 pos, Transform parent)
        {
            var go = new GameObject(kind.ToString());
            go.transform.SetParent(parent, false);
            go.transform.position = pos;
            go.transform.rotation = Quaternion.Euler(0, Random.Range(0, 360), 0);
            var e = go.AddComponent<Enemy>();
            e.def = EnemyDef.All[kind];
            e.level = level;
            float scale = 1 + (level - 1) * 0.22f;
            e.maxHp = e.hp = e.def.hp * scale;
            e.home = pos; e.wanderTarget = pos;
            e.BuildModel();
            return e;
        }

        void OnEnable() => All.Add(this);
        void OnDisable() => All.Remove(this);

        float Damage => def.damage * (1 + (level - 1) * 0.18f);

        void BuildModel()
        {
            model = new GameObject("Model").transform; model.SetParent(transform, false);
            var c = def.color;
            switch (def.kind)
            {
                case EnemyKind.Slime:
                    Mat.Prim(PrimitiveType.Sphere, model, new Vector3(0, 0.45f, 0), new Vector3(1.1f, 0.85f, 1.1f), new Color(c.r, c.g, c.b), false, 0.9f);
                    Eyes(model, 0.65f, 0.48f, 0.18f, Color.black);
                    break;
                case EnemyKind.Wolf:
                    Mat.Prim(PrimitiveType.Cube, model, new Vector3(0, 0.75f, 0), new Vector3(0.55f, 0.55f, 1.3f), c);
                    Mat.Prim(PrimitiveType.Cube, model, new Vector3(0, 0.95f, 0.8f), new Vector3(0.45f, 0.42f, 0.5f), c);
                    Mat.Prim(PrimitiveType.Cube, model, new Vector3(0, 0.85f, 1.1f), new Vector3(0.25f, 0.2f, 0.3f), c * 0.8f);
                    foreach (var s in new[] { -1, 1 }) Mat.Prim(PrimitiveType.Cube, model, new Vector3(s * 0.15f, 1.22f, 0.75f), new Vector3(0.1f, 0.18f, 0.08f), c * 0.7f);
                    Eyes(model, 1.02f, 1.05f, 0.12f, new Color(1f, 0.8f, 0.2f), 2f);
                    foreach (var x in new[] { -0.2f, 0.2f }) foreach (var z in new[] { -0.45f, 0.45f })
                        Mat.Prim(PrimitiveType.Cube, model, new Vector3(x, 0.25f, z), new Vector3(0.14f, 0.5f, 0.14f), c * 0.85f);
                    Mat.Prim(PrimitiveType.Cube, model, new Vector3(0, 0.85f, -0.8f), new Vector3(0.12f, 0.12f, 0.5f), c);
                    break;
                case EnemyKind.SkeletonArcher:
                case EnemyKind.Skeleton:
                    Mat.Prim(PrimitiveType.Capsule, model, new Vector3(0, 1.15f, 0), new Vector3(0.35f, 0.35f, 0.22f), c);
                    Mat.Prim(PrimitiveType.Sphere, model, new Vector3(0, 1.75f, 0), Vector3.one * 0.36f, c);
                    Eyes(model, 1.78f, 0.15f, 0.08f, new Color(0.3f, 0.9f, 1f), 3f);
                    foreach (var s in new[] { -0.12f, 0.12f }) Mat.Prim(PrimitiveType.Capsule, model, new Vector3(s, 0.45f, 0), new Vector3(0.1f, 0.45f, 0.1f), c);
                    foreach (var s in new[] { -0.28f, 0.28f }) Mat.Prim(PrimitiveType.Capsule, model, new Vector3(s, 1.15f, 0.05f), new Vector3(0.08f, 0.35f, 0.08f), c);
                    if (def.ranged) Mat.Prim(PrimitiveType.Cylinder, model, new Vector3(-0.32f, 1.1f, 0.25f), new Vector3(0.04f, 0.5f, 0.04f), new Color(0.3f, 0.2f, 0.1f));
                    else Mat.Prim(PrimitiveType.Cube, model, new Vector3(0.32f, 1.0f, 0.4f), new Vector3(0.05f, 0.05f, 0.8f), new Color(0.6f, 0.6f, 0.62f), false, 0.7f);
                    break;
                case EnemyKind.Goblin:
                    Mat.Prim(PrimitiveType.Sphere, model, new Vector3(0, 1.0f, 0), new Vector3(1.1f, 1.1f, 0.9f), c);
                    Mat.Prim(PrimitiveType.Sphere, model, new Vector3(0, 1.75f, 0.15f), new Vector3(0.55f, 0.5f, 0.5f), c);
                    foreach (var s in new[] { -1, 1 })
                    {
                        Mat.Prim(PrimitiveType.Cube, model, new Vector3(s * 0.35f, 1.85f, 0.1f), new Vector3(0.35f, 0.08f, 0.1f), c * 0.9f).transform.localRotation = Quaternion.Euler(0, 0, s * 20);
                        Mat.Prim(PrimitiveType.Capsule, model, new Vector3(s * 0.28f, 0.3f, 0), new Vector3(0.25f, 0.3f, 0.25f), c * 0.8f);
                    }
                    Eyes(model, 1.8f, 0.4f, 0.1f, new Color(1f, 0.3f, 0.1f), 2f);
                    Mat.Prim(PrimitiveType.Cylinder, model, new Vector3(0.65f, 1.0f, 0.3f), new Vector3(0.16f, 0.55f, 0.16f), new Color(0.4f, 0.25f, 0.1f)).transform.localRotation = Quaternion.Euler(60, 0, 0);
                    break;
                case EnemyKind.TrollBoss:
                    Mat.Prim(PrimitiveType.Sphere, model, new Vector3(0, 2.2f, 0), new Vector3(2.4f, 2.6f, 2f), c);
                    Mat.Prim(PrimitiveType.Sphere, model, new Vector3(0, 3.7f, 0.5f), new Vector3(1.1f, 1f, 1f), c * 0.95f);
                    foreach (var s in new[] { -1, 1 })
                    {
                        Mat.Prim(PrimitiveType.Capsule, model, new Vector3(s * 1.4f, 2.0f, 0.2f), new Vector3(0.6f, 1.2f, 0.6f), c * 0.9f);
                        Mat.Prim(PrimitiveType.Capsule, model, new Vector3(s * 0.6f, 0.7f, 0), new Vector3(0.7f, 0.75f, 0.7f), c * 0.8f);
                        Mat.Prim(PrimitiveType.Cube, model, new Vector3(s * 0.25f, 3.45f, 0.95f), new Vector3(0.1f, 0.3f, 0.1f), new Color(0.95f, 0.9f, 0.8f));
                    }
                    Eyes(model, 3.85f, 0.95f, 0.18f, new Color(1f, 0.2f, 0.1f), 3f);
                    Mat.Prim(PrimitiveType.Cube, model, new Vector3(0, 1.4f, 0), new Vector3(2.2f, 0.5f, 1.9f), new Color(0.35f, 0.22f, 0.1f));
                    break;
            }
            baseScale = model.localScale;
        }

        void Eyes(Transform p, float y, float z, float size, Color col, float glow = 0)
        {
            foreach (var s in new[] { -1, 1 })
                Mat.Prim(PrimitiveType.Sphere, p, new Vector3(s * size * 1.2f, y, z), Vector3.one * size, col, false, 0.8f, glow);
        }

        public void TakeDamage(float dmg, bool crit, Vector3 from)
        {
            if (!Alive) return;
            hp -= dmg;
            hitFlash = 0.12f;
            aggro = true; returning = false;
            HUD.Instance?.DamageNumber(transform.position + Vector3.up * (def.boss ? 4.5f : 2f), dmg, crit, false);
            if (hp <= 0) Die();
        }

        public void Slow(float factor, float t) { slowFactor = factor; slowTimer = t; }
        public void Stun(float t) { if (!def.boss) stunTimer = t; else stunTimer = t * 0.3f; }

        void Die()
        {
            hp = 0;
            var pc = PlayerCharacter.Instance;
            if (pc != null)
            {
                pc.Data.kills++;
                // меньше опыта за слишком слабых врагов
                int diff = pc.Data.level - level;
                float mult = diff > 4 ? Mathf.Max(0.2f, 1 - (diff - 4) * 0.2f) : 1f;
                pc.GainXp(Mathf.Max(1, Mathf.RoundToInt(def.xp * (1 + (level - 1) * 0.25f) * mult)));
            }
            LootPickup.DropFor(this);
            FX.Burst(transform.position + Vector3.up * 0.8f, def.radius * 2.2f, def.color, 0.4f);
            onDeath?.Invoke(this);
            Destroy(gameObject, 0.05f);
            enabled = false;
        }

        Transform ChooseTarget()
        {
            Transform best = null; float bestD = def.aggroRange * (aggro ? 2.2f : 1f);
            var pc = PlayerCharacter.Instance;
            if (pc != null && !pc.Dead)
            {
                float d = Flat(pc.transform.position - transform.position).magnitude;
                if (d < bestD) { bestD = d; best = pc.transform; }
            }
            foreach (var m in Minion.All)
            {
                float d = Flat(m.transform.position - transform.position).magnitude;
                if (d < bestD * 0.8f) { bestD = d; best = m.transform; }
            }
            return best;
        }

        static Vector3 Flat(Vector3 v) { v.y = 0; return v; }

        void Update()
        {
            if (!Alive) return;
            float dt = Time.deltaTime;
            if (attackTimer > 0) attackTimer -= dt;
            if (slowTimer > 0) { slowTimer -= dt; if (slowTimer <= 0) slowFactor = 1; }
            Animate(dt);
            if (stunTimer > 0) { stunTimer -= dt; return; }

            float speed = def.speed * slowFactor;
            float homeDist = Flat(transform.position - home).magnitude;
            if (homeDist > (def.boss ? 22 : 28)) { returning = true; aggro = false; }

            if (returning)
            {
                MoveTowards(home, speed * 1.5f, dt);
                hp = Mathf.Min(maxHp, hp + maxHp * 0.25f * dt);
                if (homeDist < 1.5f) returning = false;
                return;
            }

            Target = ChooseTarget();
            if (Target != null)
            {
                aggro = true;
                var to = Flat(Target.position - transform.position);
                float dist = to.magnitude;
                Face(to, dt);
                if (def.boss) BossLogic(dt);
                if (dist > def.attackRange * 0.9f) MoveTowards(Target.position, speed, dt);
                else if (attackTimer <= 0)
                {
                    attackTimer = def.attackInterval;
                    Attack();
                }
            }
            else
            {
                aggro = false;
                wanderTimer -= dt;
                if (wanderTimer <= 0)
                {
                    wanderTimer = Random.Range(2.5f, 6f);
                    var r = Random.insideUnitCircle * 6f;
                    wanderTarget = home + new Vector3(r.x, 0, r.y);
                }
                if (Flat(wanderTarget - transform.position).magnitude > 0.5f) MoveTowards(wanderTarget, speed * 0.4f, dt);
            }
        }

        void Attack()
        {
            animPhase = 0; lunge = 0.25f;
            var t = Target;
            if (def.ranged)
            {
                var origin = transform.position + Vector3.up * 1.3f + transform.forward * 0.4f;
                var dir = Flat(t.position - transform.position).normalized;
                Projectile.Fire(origin, dir, 13f, def.attackRange + 4, new Color(0.6f, 0.9f, 1f), 0.25f, false, null, Damage);
            }
            else DealTo(t, Damage);
        }

        void DealTo(Transform t, float dmg)
        {
            if (t == null) return;
            var pc = t.GetComponent<PlayerCharacter>();
            if (pc != null) { pc.TakeDamage(dmg, transform.position); return; }
            var m = t.GetComponent<Minion>();
            if (m != null) m.TakeDamage(dmg);
        }

        void BossLogic(float dt)
        {
            bossSkillTimer -= dt;
            if (bossSkillTimer > 0 || Target == null) return;
            bossSkillTimer = Random.Range(5f, 7.5f);
            var pos = Target.position;
            const float r = 4.5f;
            FX.Telegraph(pos, r, 1.3f);
            StartCoroutine(Slam(pos, r));
        }

        System.Collections.IEnumerator Slam(Vector3 pos, float r)
        {
            yield return new WaitForSeconds(1.3f);
            if (!Alive) yield break;
            FX.Ring(pos, r, new Color(0.6f, 0.4f, 0.2f), 0.4f);
            var pc = PlayerCharacter.Instance;
            if (pc != null && Flat(pc.transform.position - pos).magnitude < r) pc.TakeDamage(Damage * 1.8f, pos);
            foreach (var m in new List<Minion>(Minion.All)) if (Flat(m.transform.position - pos).magnitude < r) m.TakeDamage(Damage * 1.8f);
        }

        float lunge;

        void MoveTowards(Vector3 p, float speed, float dt)
        {
            var d = Flat(p - transform.position);
            if (d.sqrMagnitude < 0.01f) return;
            var step = d.normalized * speed * dt;
            // разведение врагов, чтобы не слипались
            foreach (var o in All)
            {
                if (o == this) continue;
                var away = Flat(transform.position - o.transform.position);
                float min = Radius + o.Radius;
                if (away.sqrMagnitude < min * min && away.sqrMagnitude > 0.0001f) step += away.normalized * dt * 2f;
            }
            var np = transform.position + step;
            np.y = 0;
            transform.position = np;
            Face(d, dt);
        }

        void Face(Vector3 d, float dt)
        {
            if (d.sqrMagnitude < 0.001f) return;
            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(d), dt * 8f);
        }

        void Animate(float dt)
        {
            animPhase += dt * 8f;
            float sq = def.kind == EnemyKind.Slime ? Mathf.Sin(animPhase) * 0.12f : 0;
            float bob = def.kind != EnemyKind.Slime ? Mathf.Abs(Mathf.Sin(animPhase)) * 0.06f : 0;
            if (lunge > 0) lunge -= dt;
            float fwd = lunge > 0 ? Mathf.Sin(lunge / 0.25f * Mathf.PI) * 0.5f : 0;
            float flash = hitFlash > 0 ? 1.12f : 1f;
            if (hitFlash > 0) hitFlash -= dt;
            model.localScale = new Vector3(baseScale.x * (1 + sq) * flash, baseScale.y * (1 - sq) * flash, baseScale.z * (1 + sq) * flash);
            model.localPosition = new Vector3(0, bob, fwd);
            if (stunTimer > 0) model.localRotation = Quaternion.Euler(0, 0, Mathf.Sin(Time.time * 20) * 8);
            else model.localRotation = Quaternion.identity;
        }
    }
}
