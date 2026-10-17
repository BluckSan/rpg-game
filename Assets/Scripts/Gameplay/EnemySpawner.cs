using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    /// <summary>Область появления врагов с периодическим возрождением.</summary>
    public class EnemySpawner : MonoBehaviour
    {
        public EnemyKind kind;
        public int minLevel = 1, maxLevel = 2, count = 4;
        public float radius = 8f, respawnTime = 25f;
        public string killFlag; // для боссов: флаг в сохранении зоны (на будущее)
        readonly List<Enemy> alive = new List<Enemy>();
        readonly List<float> pending = new List<float>();

        public static EnemySpawner Create(Transform parent, Vector3 pos, EnemyKind kind, int minL, int maxL, int count, float radius, float respawn = 25f)
        {
            var go = new GameObject("Spawner_" + kind); go.transform.SetParent(parent, false); go.transform.position = pos;
            var s = go.AddComponent<EnemySpawner>();
            s.kind = kind; s.minLevel = minL; s.maxLevel = maxL; s.count = count; s.radius = radius; s.respawnTime = respawn;
            return s;
        }

        void Start() { for (int i = 0; i < count; i++) SpawnOne(); }

        void SpawnOne()
        {
            var r = Random.insideUnitCircle * radius;
            var e = Enemy.Spawn(kind, Random.Range(minLevel, maxLevel + 1), transform.position + new Vector3(r.x, 0, r.y), transform);
            e.onDeath = OnDeath;
            alive.Add(e);
        }

        void OnDeath(Enemy e)
        {
            alive.Remove(e);
            pending.Add(respawnTime);
            if (!string.IsNullOrEmpty(killFlag) && PlayerCharacter.Instance != null)
            {
                var z = PlayerCharacter.Instance.Data.GetZone(PlayerCharacter.Instance.Data.zoneId);
                if (!z.flags.Contains(killFlag)) { z.flags.Add(killFlag); Toast.Show($"Повержен: {e.def.name}!", 4f); }
            }
        }

        void Update()
        {
            for (int i = pending.Count - 1; i >= 0; i--)
            {
                pending[i] -= Time.deltaTime;
                if (pending[i] <= 0)
                {
                    // не появляться прямо перед игроком
                    var pc = PlayerCharacter.Instance;
                    if (pc != null && Vector3.Distance(pc.transform.position, transform.position) < radius + 6) { pending[i] = 3; continue; }
                    pending.RemoveAt(i); SpawnOne();
                }
            }
        }
    }
}
