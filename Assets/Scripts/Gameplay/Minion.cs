using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    /// <summary>Призванный союзник (скелет некроманта).</summary>
    public class Minion : MonoBehaviour
    {
        public static readonly List<Minion> All = new List<Minion>();
        PlayerCombat owner; float mult, life, hp, attackTimer;
        Transform model;

        public static Minion Spawn(Vector3 pos, PlayerCombat owner, float mult, float life)
        {
            var go = new GameObject("Minion"); go.transform.position = new Vector3(pos.x, 0, pos.z);
            var m = go.AddComponent<Minion>();
            m.owner = owner; m.mult = mult; m.life = life;
            m.hp = PlayerCharacter.Instance.Stats.MaxHp * 0.5f;
            m.model = new GameObject("Model").transform; m.model.SetParent(go.transform, false);
            var c = new Color(0.75f, 0.7f, 0.95f);
            Mat.Prim(PrimitiveType.Capsule, m.model, new Vector3(0, 1f, 0), new Vector3(0.35f, 0.5f, 0.25f), c);
            Mat.Prim(PrimitiveType.Sphere, m.model, new Vector3(0, 1.7f, 0), Vector3.one * 0.35f, c);
            Mat.Prim(PrimitiveType.Sphere, m.model, new Vector3(0.08f, 1.73f, 0.15f), Vector3.one * 0.08f, new Color(0.6f, 1f, 0.6f), false, 0.8f, 3f);
            Mat.Prim(PrimitiveType.Sphere, m.model, new Vector3(-0.08f, 1.73f, 0.15f), Vector3.one * 0.08f, new Color(0.6f, 1f, 0.6f), false, 0.8f, 3f);
            Mat.Prim(PrimitiveType.Cube, m.model, new Vector3(0.3f, 1.0f, 0.4f), new Vector3(0.05f, 0.05f, 0.8f), new Color(0.6f, 0.6f, 0.62f));
            FX.Burst(go.transform.position + Vector3.up, 1.2f, c, 0.4f);
            return m;
        }

        void OnEnable() => All.Add(this);
        void OnDisable() => All.Remove(this);

        public void TakeDamage(float d) { hp -= d; if (hp <= 0) Die(); }

        void Die() { FX.Burst(transform.position + Vector3.up, 1f, Color.white, 0.3f); Destroy(gameObject); enabled = false; }

        void Update()
        {
            life -= Time.deltaTime; if (life <= 0 || owner == null) { Die(); return; }
            if (attackTimer > 0) attackTimer -= Time.deltaTime;
            Enemy target = null; float best = 14f;
            foreach (var e in Enemy.All)
            {
                if (!e.Alive) continue;
                float d = Vector3.Distance(e.transform.position, transform.position);
                if (d < best) { best = d; target = e; }
            }
            Vector3 goal = target != null ? target.transform.position : owner.transform.position + owner.transform.right * 2f;
            var to = goal - transform.position; to.y = 0;
            float stop = target != null ? target.Radius + 1.2f : 2f;
            if (to.magnitude > stop)
            {
                transform.position += to.normalized * 5f * Time.deltaTime;
                transform.rotation = Quaternion.LookRotation(to);
            }
            else if (target != null && attackTimer <= 0)
            {
                attackTimer = 1f;
                owner.Hit(target, mult, true);
            }
            model.localPosition = new Vector3(0, Mathf.Abs(Mathf.Sin(Time.time * 8)) * 0.08f, 0);
        }
    }
}
