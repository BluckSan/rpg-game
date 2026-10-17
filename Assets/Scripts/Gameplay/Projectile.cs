using UnityEngine;

namespace RPG
{
    /// <summary>Снаряд (стрела, искра, огненный шар). Попадание проверяется по расстоянию.</summary>
    public class Projectile : MonoBehaviour
    {
        Vector3 dir; float speed, maxDist, traveled, size, damage;
        bool fromPlayer;
        System.Action<Enemy> onHit;

        public static Projectile Fire(Vector3 origin, Vector3 dir, float speed, float range, Color c, float size, bool fromPlayer, System.Action<Enemy> onHit, float damage = 0)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            Destroy(go.GetComponent<Collider>());
            go.transform.position = origin;
            go.transform.localScale = new Vector3(size, size, size * (size < 0.3f ? 3f : 1f));
            go.transform.rotation = Quaternion.LookRotation(dir);
            go.GetComponent<Renderer>().sharedMaterial = Mat.Get(c, 0.5f, 2f);
            go.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            var p = go.AddComponent<Projectile>();
            p.dir = dir.normalized; p.speed = speed; p.maxDist = range; p.size = size;
            p.fromPlayer = fromPlayer; p.onHit = onHit; p.damage = damage;
            return p;
        }

        void Update()
        {
            float step = speed * Time.deltaTime;
            transform.position += dir * step;
            traveled += step;
            var pos = transform.position;
            if (fromPlayer)
            {
                foreach (var e in Enemy.All)
                {
                    if (!e.Alive) continue;
                    var d = e.transform.position - pos; d.y = 0;
                    if (d.magnitude < e.Radius + size + 0.3f) { onHit?.Invoke(e); Destroy(gameObject); return; }
                }
            }
            else
            {
                var pc = PlayerCharacter.Instance;
                if (pc != null && !pc.Dead)
                {
                    var d = pc.transform.position - pos; d.y = 0;
                    if (d.magnitude < 0.6f + size) { pc.TakeDamage(damage, pos); Destroy(gameObject); return; }
                }
                foreach (var m in Minion.All)
                {
                    var d = m.transform.position - pos; d.y = 0;
                    if (d.magnitude < 0.6f + size) { m.TakeDamage(damage); Destroy(gameObject); return; }
                }
            }
            if (traveled > maxDist) Destroy(gameObject);
        }
    }
}
