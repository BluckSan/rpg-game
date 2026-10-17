using UnityEngine;

namespace RPG
{
    /// <summary>
    /// Строит стартовую зону «Пепельная долина» из примитивов (одиночная локация).
    /// Лагерь в центре, луг со слизнями, лес с волками, кладбище скелетов, лагерь гоблинов, руины с боссом, портал.
    /// </summary>
    public class StarterZoneBuilder : MonoBehaviour
    {
        Transform statics, enemies;
        const float Size = 90f; // половина размера зоны

        static readonly Color Grass = new Color(0.33f, 0.47f, 0.24f);
        static readonly Color GrassDark = new Color(0.26f, 0.38f, 0.2f);
        static readonly Color Dirt = new Color(0.45f, 0.36f, 0.25f);
        static readonly Color Stone = new Color(0.5f, 0.5f, 0.52f);
        static readonly Color Wood = new Color(0.4f, 0.27f, 0.15f);

        public void Build()
        {
            Random.InitState(1337);
            statics = new GameObject("Static").transform; statics.SetParent(transform, false);
            enemies = new GameObject("Enemies").transform; enemies.SetParent(transform, false);

            SetupLighting();
            Ground();
            Camp(Vector3.zero);
            Meadow(new Vector3(28, 0, 22));
            Forest(new Vector3(-42, 0, 8));
            Graveyard(new Vector3(6, 0, -46));
            GoblinCamp(new Vector3(52, 0, -14));
            Ruins(new Vector3(-4, 0, 60));
            PortalArch(new Vector3(66, 0, 56));
            Scatter();
            Boundary();

            // спавны
            EnemySpawner.Create(enemies, new Vector3(28, 0, 22), EnemyKind.Slime, 1, 2, 6, 9, 15);
            EnemySpawner.Create(enemies, new Vector3(16, 0, -14), EnemyKind.Slime, 1, 3, 4, 6, 18);
            EnemySpawner.Create(enemies, new Vector3(-36, 0, 14), EnemyKind.Wolf, 2, 4, 4, 8, 22);
            EnemySpawner.Create(enemies, new Vector3(-52, 0, -4), EnemyKind.Wolf, 3, 5, 4, 8, 22);
            EnemySpawner.Create(enemies, new Vector3(6, 0, -46), EnemyKind.SkeletonArcher, 3, 5, 4, 8, 25);
            EnemySpawner.Create(enemies, new Vector3(-6, 0, -52), EnemyKind.Skeleton, 4, 6, 3, 6, 25);
            EnemySpawner.Create(enemies, new Vector3(52, 0, -14), EnemyKind.Goblin, 5, 7, 4, 7, 30);
            EnemySpawner.Create(enemies, new Vector3(-30, 0, 46), EnemyKind.Skeleton, 6, 8, 4, 7, 30);
            var boss = EnemySpawner.Create(enemies, new Vector3(-4, 0, 64), EnemyKind.TrollBoss, 9, 9, 1, 0.5f, 120);
            boss.killFlag = "boss_troll_killed";

            StaticBatchingUtility.Combine(statics.gameObject);
        }

        void SetupLighting()
        {
            var sun = new GameObject("Sun").AddComponent<Light>();
            sun.type = LightType.Directional; sun.intensity = 1.15f; sun.color = new Color(1f, 0.93f, 0.8f);
            sun.shadows = LightShadows.Soft; sun.shadowStrength = 0.75f;
            sun.transform.rotation = Quaternion.Euler(48, -35, 0);
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.55f, 0.62f, 0.75f);
            RenderSettings.ambientEquatorColor = new Color(0.42f, 0.42f, 0.38f);
            RenderSettings.ambientGroundColor = new Color(0.22f, 0.2f, 0.16f);
            RenderSettings.fog = true; RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogColor = new Color(0.62f, 0.7f, 0.78f);
            RenderSettings.fogStartDistance = 45; RenderSettings.fogEndDistance = 130;
            QualitySettings.shadowDistance = 45;
        }

        GameObject Solid(PrimitiveType t, Vector3 pos, Vector3 scale, Color c, float rotY = 0, bool collider = true)
        {
            var g = Mat.Prim(t, statics, pos, scale, c, collider);
            g.transform.localRotation = Quaternion.Euler(0, rotY, 0);
            return g;
        }

        void Ground()
        {
            Solid(PrimitiveType.Cube, new Vector3(0, -0.5f, 0), new Vector3(Size * 2 + 40, 1, Size * 2 + 40), Grass);
            // тропы от лагеря
            Path(Vector3.zero, new Vector3(28, 0, 22));
            Path(Vector3.zero, new Vector3(-42, 0, 8));
            Path(Vector3.zero, new Vector3(6, 0, -46));
            Path(Vector3.zero, new Vector3(52, 0, -14));
            Path(Vector3.zero, new Vector3(-4, 0, 60));
            Path(new Vector3(28, 0, 22), new Vector3(66, 0, 56));
            // пятна травы
            for (int i = 0; i < 60; i++)
            {
                var p = RandPos(Size - 5);
                var s = Random.Range(4f, 12f);
                Solid(PrimitiveType.Cylinder, new Vector3(p.x, 0.005f, p.z), new Vector3(s, 0.01f, s * Random.Range(0.6f, 1f)), Random.value < 0.5f ? GrassDark : new Color(0.38f, 0.52f, 0.26f), Random.Range(0, 360), false);
            }
        }

        void Path(Vector3 a, Vector3 b)
        {
            var d = b - a; var mid = (a + b) / 2;
            Solid(PrimitiveType.Cube, new Vector3(mid.x, 0.01f, mid.z), new Vector3(3.2f, 0.02f, d.magnitude), Dirt, Quaternion.LookRotation(d).eulerAngles.y, false);
        }

        void Camp(Vector3 c)
        {
            var sp = new GameObject("SpawnPoint"); sp.transform.position = c + new Vector3(0, 0.1f, -3.5f);
            // костёр
            Solid(PrimitiveType.Cylinder, c + new Vector3(0, 0.08f, 0), new Vector3(1.8f, 0.08f, 1.8f), Stone, 0, true);
            for (int i = 0; i < 4; i++) Solid(PrimitiveType.Cylinder, c + new Vector3(0, 0.25f, 0), new Vector3(0.15f, 0.6f, 0.15f), Wood, 0, false).transform.localRotation = Quaternion.Euler(70, i * 90, 0);
            var fire = Mat.Prim(PrimitiveType.Sphere, transform, c + new Vector3(0, 0.55f, 0), new Vector3(0.6f, 0.9f, 0.6f), new Color(1f, 0.55f, 0.1f), false, 0f, 3f);
            fire.AddComponent<Flicker>();
            var l = new GameObject("FireLight").AddComponent<Light>(); l.type = LightType.Point; l.range = 12; l.intensity = 2.2f; l.color = new Color(1f, 0.6f, 0.25f);
            l.transform.position = c + new Vector3(0, 1.5f, 0); l.gameObject.AddComponent<Flicker>();
            // палатки
            for (int i = 0; i < 3; i++)
            {
                float a = 40 + i * 110;
                var p = c + Quaternion.Euler(0, a, 0) * Vector3.forward * 7;
                var tent = Solid(PrimitiveType.Cube, p + Vector3.up * 1.1f, new Vector3(2.6f, 2.6f, 3.4f), new Color(0.7f, 0.6f, 0.45f), a);
                tent.transform.localRotation = Quaternion.Euler(0, a, 45);
                Solid(PrimitiveType.Cube, p + Vector3.up * 0.05f, new Vector3(3.8f, 0.1f, 3.6f), Dirt, a, false);
            }
            // ящики и бочки
            for (int i = 0; i < 6; i++)
            {
                var p = c + Quaternion.Euler(0, i * 60 + 15, 0) * Vector3.forward * Random.Range(4f, 5.5f);
                if (i % 2 == 0) Solid(PrimitiveType.Cube, p + Vector3.up * 0.4f, Vector3.one * 0.8f, Wood * 1.2f, Random.Range(0, 90));
                else Solid(PrimitiveType.Cylinder, p + Vector3.up * 0.5f, new Vector3(0.7f, 0.5f, 0.7f), Wood);
            }
            // частокол
            for (int i = 0; i < 40; i++)
            {
                float a = i * 9;
                if (a > 15 && a < 40 || a > 105 && a < 130 || a > 185 && a < 210 || a > 255 && a < 280 || a > 340 && a < 360 || a < 3) continue;
                var p = c + Quaternion.Euler(0, a, 0) * Vector3.forward * 12;
                Solid(PrimitiveType.Cylinder, p + Vector3.up * 1f, new Vector3(0.35f, 1f, 0.35f), Wood * 0.9f);
            }
            Sign(c + new Vector3(2.5f, 0, -6), "Лагерь");
        }

        void Sign(Vector3 p, string text)
        {
            Solid(PrimitiveType.Cylinder, p + Vector3.up * 0.8f, new Vector3(0.12f, 0.8f, 0.12f), Wood);
            Solid(PrimitiveType.Cube, p + Vector3.up * 1.5f, new Vector3(1.2f, 0.5f, 0.08f), Wood * 1.3f);
        }

        void Tree(Vector3 p, float s, bool pine)
        {
            Solid(PrimitiveType.Cylinder, p + Vector3.up * 1.2f * s, new Vector3(0.35f * s, 1.2f * s, 0.35f * s), Wood);
            if (pine)
            {
                var col = new Color(0.16f, 0.32f, 0.18f) * Random.Range(0.85f, 1.15f); col.a = 1;
                for (int i = 0; i < 3; i++)
                    Solid(PrimitiveType.Cube, p + Vector3.up * (2.2f + i * 1.1f) * s, new Vector3((2.4f - i * 0.6f) * s, 1.2f * s, (2.4f - i * 0.6f) * s), col, Random.Range(0, 90), false).transform.localRotation = Quaternion.Euler(0, 45 + i * 20, 0);
            }
            else
            {
                var col = new Color(0.25f, 0.45f, 0.2f) * Random.Range(0.85f, 1.15f); col.a = 1;
                Solid(PrimitiveType.Sphere, p + Vector3.up * 3f * s, new Vector3(2.8f, 2.4f, 2.8f) * s, col, 0, false);
                Solid(PrimitiveType.Sphere, p + new Vector3(0.6f, 3.6f, 0.3f) * s, new Vector3(1.8f, 1.6f, 1.8f) * s, col * 1.1f, 0, false);
            }
        }

        void Rock(Vector3 p, float s)
        {
            var g = Solid(PrimitiveType.Sphere, p + Vector3.up * 0.3f * s, new Vector3(1.4f, 0.9f, 1.2f) * s, Stone * Random.Range(0.8f, 1.1f), Random.Range(0, 360));
            g.transform.localRotation = Quaternion.Euler(Random.Range(-10, 10), Random.Range(0, 360), Random.Range(-10, 10));
        }

        void Meadow(Vector3 c)
        {
            for (int i = 0; i < 40; i++)
            {
                var p = c + Flat(Random.insideUnitCircle * 14);
                var col = new[] { new Color(1f, 0.85f, 0.2f), new Color(0.9f, 0.3f, 0.4f), new Color(0.6f, 0.5f, 1f), Color.white }[Random.Range(0, 4)];
                Solid(PrimitiveType.Sphere, p + Vector3.up * 0.25f, Vector3.one * 0.22f, col, 0, false);
                Solid(PrimitiveType.Cylinder, p + Vector3.up * 0.12f, new Vector3(0.04f, 0.12f, 0.04f), GrassDark, 0, false);
            }
            for (int i = 0; i < 5; i++) Rock(c + Flat(Random.insideUnitCircle * 15), Random.Range(0.6f, 1.2f));
        }

        void Forest(Vector3 c)
        {
            for (int i = 0; i < 70; i++)
            {
                var p = c + Flat(Random.insideUnitCircle * 26);
                if ((p - new Vector3(-36, 0, 14)).magnitude < 5 || (p - new Vector3(-52, 0, -4)).magnitude < 5) continue;
                if (DistToPath(p) < 3) continue;
                Tree(p, Random.Range(0.8f, 1.4f), Random.value < 0.6f);
            }
            for (int i = 0; i < 10; i++) Rock(c + Flat(Random.insideUnitCircle * 22), Random.Range(0.5f, 1.4f));
        }

        void Graveyard(Vector3 c)
        {
            Solid(PrimitiveType.Cube, c + new Vector3(0, 0.01f, 0), new Vector3(22, 0.02f, 18), new Color(0.3f, 0.32f, 0.25f), 0, false);
            for (int x = -3; x <= 3; x++) for (int z = -2; z <= 2; z++)
            {
                if (Random.value < 0.3f) continue;
                var p = c + new Vector3(x * 3f + Random.Range(-0.4f, 0.4f), 0, z * 3.2f + Random.Range(-0.4f, 0.4f));
                var g = Solid(PrimitiveType.Cube, p + Vector3.up * 0.6f, new Vector3(0.9f, 1.2f, 0.25f), Stone * 0.85f, Random.Range(-15, 15));
                g.transform.localRotation = Quaternion.Euler(Random.Range(-8, 8), Random.Range(-15, 15), Random.Range(-8, 8));
            }
            // ограда
            for (int i = -5; i <= 5; i++)
            {
                Solid(PrimitiveType.Cube, c + new Vector3(i * 2.2f, 0.6f, 9.5f), new Vector3(0.2f, 1.2f, 0.2f), new Color(0.2f, 0.2f, 0.22f));
                if (i != 0) Solid(PrimitiveType.Cube, c + new Vector3(i * 2.2f, 0.6f, -9.5f), new Vector3(0.2f, 1.2f, 0.2f), new Color(0.2f, 0.2f, 0.22f));
            }
            // склеп
            Solid(PrimitiveType.Cube, c + new Vector3(0, 1.5f, -6.5f), new Vector3(5, 3, 3), Stone * 0.7f);
            Solid(PrimitiveType.Cube, c + new Vector3(0, 3.3f, -6.5f), new Vector3(5.6f, 0.6f, 3.6f), Stone * 0.6f);
            for (int i = 0; i < 6; i++) Tree(c + Flat(Random.insideUnitCircle.normalized * Random.Range(12f, 16f)), Random.Range(0.8f, 1.1f), false);
        }

        void GoblinCamp(Vector3 c)
        {
            for (int i = 0; i < 3; i++)
            {
                var p = c + Quaternion.Euler(0, i * 120 + 20, 0) * Vector3.forward * 6;
                Solid(PrimitiveType.Cylinder, p + Vector3.up * 1.2f, new Vector3(3, 1.2f, 3), new Color(0.45f, 0.35f, 0.25f));
                Solid(PrimitiveType.Sphere, p + Vector3.up * 2.4f, new Vector3(3.2f, 1.8f, 3.2f), new Color(0.5f, 0.4f, 0.2f), 0, false);
            }
            for (int i = 0; i < 24; i++)
            {
                float a = i * 15;
                if (a > 230 && a < 280) continue; // проход к лагерю
                var p = c + Quaternion.Euler(0, a, 0) * Vector3.forward * 11;
                var g = Solid(PrimitiveType.Cylinder, p + Vector3.up * 1.3f, new Vector3(0.4f, 1.3f, 0.4f), Wood * 0.8f);
            }
            Solid(PrimitiveType.Cylinder, c + Vector3.up * 0.1f, new Vector3(1.5f, 0.1f, 1.5f), new Color(0.2f, 0.18f, 0.15f));
            for (int i = 0; i < 4; i++) Solid(PrimitiveType.Cube, c + Flat(Random.insideUnitCircle * 4) + Vector3.up * 0.25f, new Vector3(0.6f, 0.5f, 0.4f), new Color(0.85f, 0.8f, 0.7f), Random.Range(0, 360), false);
        }

        void Ruins(Vector3 c)
        {
            Solid(PrimitiveType.Cylinder, c + new Vector3(0, 0.1f, 4), new Vector3(24, 0.1f, 24), Stone * 0.75f);
            for (int i = 0; i < 12; i++)
            {
                float a = i * 30;
                var p = c + new Vector3(0, 0, 4) + Quaternion.Euler(0, a, 0) * Vector3.forward * 11;
                float h = i % 3 == 0 ? Random.Range(1f, 2.5f) : Random.Range(4f, 6f);
                if (i == 6) continue; // вход со стороны лагеря
                Solid(PrimitiveType.Cylinder, p + Vector3.up * h / 2, new Vector3(1.2f, h / 2, 1.2f), Stone * 0.9f);
                if (i % 3 == 0) Rock(p + new Vector3(1.5f, 0, 1f), 0.8f);
            }
            Solid(PrimitiveType.Cube, c + new Vector3(0, 1.5f, 14), new Vector3(8, 3, 1.5f), Stone * 0.8f);
            var crystal = Mat.Prim(PrimitiveType.Cube, transform, c + new Vector3(0, 3.8f, 14), new Vector3(1f, 1.6f, 1f), new Color(0.5f, 0.3f, 0.9f), false, 0.9f, 2.5f);
            crystal.transform.rotation = Quaternion.Euler(0, 45, 0);
            crystal.AddComponent<Spin>().speed = new Vector3(0, 40, 0);
            var l = new GameObject("CrystalLight").AddComponent<Light>(); l.type = LightType.Point; l.range = 14; l.intensity = 1.8f; l.color = new Color(0.6f, 0.4f, 1f);
            l.transform.position = c + new Vector3(0, 4.5f, 12);
        }

        void PortalArch(Vector3 c)
        {
            var rot = Quaternion.Euler(0, -135, 0);
            foreach (var s in new[] { -1, 1 })
                Solid(PrimitiveType.Cube, c + rot * new Vector3(s * 2f, 2.2f, 0), new Vector3(0.9f, 4.4f, 0.9f), Stone * 0.8f, -135);
            Solid(PrimitiveType.Cube, c + rot * new Vector3(0, 4.7f, 0), new Vector3(5.2f, 0.8f, 1f), Stone * 0.75f, -135);
            var plane = Mat.Prim(PrimitiveType.Cube, transform, c + Vector3.up * 2.1f, new Vector3(3.1f, 4.1f, 0.1f), new Color(0.3f, 0.8f, 1f), false, 0.9f, 2f);
            plane.transform.rotation = rot;
            plane.GetComponent<Renderer>().sharedMaterial = Mat.Transparent(new Color(0.3f, 0.8f, 1f, 0.55f));
            var portal = new GameObject("Portal_Global"); portal.transform.position = c;
            portal.AddComponent<Portal>().targetZone = ZoneRegistry.GlobalZone;
            var l = new GameObject("PortalLight").AddComponent<Light>(); l.type = LightType.Point; l.range = 10; l.intensity = 2f; l.color = new Color(0.3f, 0.8f, 1f);
            l.transform.position = c + Vector3.up * 2.5f;
        }

        void Scatter()
        {
            for (int i = 0; i < 90; i++)
            {
                var p = RandPos(Size - 6);
                if (p.magnitude < 16 || DistToPath(p) < 3) continue;
                if ((p - new Vector3(-4, 0, 64)).magnitude < 16 || (p - new Vector3(52, 0, -14)).magnitude < 13 || (p - new Vector3(6, 0, -46)).magnitude < 13 || (p - new Vector3(66, 0, 56)).magnitude < 6) continue;
                if (Random.value < 0.65f) Tree(p, Random.Range(0.7f, 1.3f), Random.value < 0.4f); else Rock(p, Random.Range(0.5f, 1.6f));
            }
        }

        void Boundary()
        {
            // кольцо гор
            for (int i = 0; i < 72; i++)
            {
                float a = i * 5;
                var p = Quaternion.Euler(0, a, 0) * Vector3.forward * (Size + Random.Range(0f, 6f));
                float s = Random.Range(8f, 16f);
                Solid(PrimitiveType.Sphere, p + Vector3.up * s * 0.2f, new Vector3(s, s * Random.Range(0.8f, 1.3f), s), Stone * Random.Range(0.6f, 0.85f), Random.Range(0, 360));
            }
            // невидимые стены
            for (int i = 0; i < 4; i++)
            {
                var w = new GameObject("Wall").AddComponent<BoxCollider>();
                w.transform.SetParent(transform, false);
                w.transform.rotation = Quaternion.Euler(0, i * 90, 0);
                w.transform.position = w.transform.rotation * new Vector3(0, 5, Size - 4);
                w.size = new Vector3(Size * 2, 10, 1);
            }
        }

        static readonly Vector3[][] paths =
        {
            new[]{Vector3.zero,new Vector3(28,0,22)}, new[]{Vector3.zero,new Vector3(-42,0,8)}, new[]{Vector3.zero,new Vector3(6,0,-46)},
            new[]{Vector3.zero,new Vector3(52,0,-14)}, new[]{Vector3.zero,new Vector3(-4,0,60)}, new[]{new Vector3(28,0,22),new Vector3(66,0,56)}
        };

        static float DistToPath(Vector3 p)
        {
            float best = float.MaxValue;
            foreach (var s in paths)
            {
                var ab = s[1] - s[0]; float t = Mathf.Clamp01(Vector3.Dot(p - s[0], ab) / ab.sqrMagnitude);
                best = Mathf.Min(best, Vector3.Distance(p, s[0] + ab * t));
            }
            return best;
        }

        static Vector3 Flat(Vector2 v) => new Vector3(v.x, 0, v.y);
        static Vector3 RandPos(float r) => new Vector3(Random.Range(-r, r), 0, Random.Range(-r, r));
    }

    public class Flicker : MonoBehaviour
    {
        Light l; float baseI; Vector3 baseS;
        void Start() { l = GetComponent<Light>(); if (l) baseI = l.intensity; baseS = transform.localScale; }
        void Update()
        {
            float n = Mathf.PerlinNoise(Time.time * 6f, transform.position.x);
            if (l) l.intensity = baseI * (0.75f + n * 0.5f);
            else transform.localScale = baseS * (0.85f + n * 0.3f);
        }
    }
}
