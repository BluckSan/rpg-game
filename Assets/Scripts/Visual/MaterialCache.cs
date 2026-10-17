using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    /// <summary>Материалы для примитивов. Базовые материалы лежат в Resources/Materials (создаёт ProjectSetup),
    /// это гарантирует, что шейдеры попадут в сборку.</summary>
    public static class Mat
    {
        static Material baseMat, emissiveMat, fxMat;
        static readonly Dictionary<int, Material> cache = new Dictionary<int, Material>();
        static readonly Dictionary<int, Material> fxCache = new Dictionary<int, Material>();

        static Material Base
        {
            get
            {
                if (baseMat == null)
                {
                    baseMat = Resources.Load<Material>("Materials/Base");
                    if (baseMat == null) baseMat = new Material(Shader.Find("Standard"));
                }
                return baseMat;
            }
        }

        static Material Emissive
        {
            get
            {
                if (emissiveMat == null)
                {
                    emissiveMat = Resources.Load<Material>("Materials/BaseEmissive");
                    if (emissiveMat == null) { emissiveMat = new Material(Base); emissiveMat.EnableKeyword("_EMISSION"); }
                }
                return emissiveMat;
            }
        }

        static Material Fx
        {
            get
            {
                if (fxMat == null)
                {
                    fxMat = Resources.Load<Material>("Materials/FX");
                    if (fxMat == null) fxMat = new Material(Shader.Find("Sprites/Default"));
                }
                return fxMat;
            }
        }

        static int Key(Color c, float g, float e) =>
            ((int)(c.r * 63) << 18) ^ ((int)(c.g * 63) << 12) ^ ((int)(c.b * 63) << 6) ^ (int)(c.a * 63) ^ ((int)(g * 7) << 24) ^ ((int)(e * 7) << 27);

        public static Material Get(Color c, float gloss = 0.2f, float emission = 0f)
        {
            int k = Key(c, gloss, emission);
            if (cache.TryGetValue(k, out var m) && m != null) return m;
            m = new Material(emission > 0 ? Emissive : Base) { color = c };
            if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", gloss);
            if (emission > 0 && m.HasProperty("_EmissionColor"))
            {
                m.EnableKeyword("_EMISSION");
                m.SetColor("_EmissionColor", c * emission);
            }
            cache[k] = m;
            return m;
        }

        /// <summary>Полупрозрачный неосвещённый материал для эффектов.</summary>
        public static Material Transparent(Color c)
        {
            int k = Key(c, 0, 0);
            if (fxCache.TryGetValue(k, out var m) && m != null) return m;
            m = new Material(Fx) { color = c };
            fxCache[k] = m;
            return m;
        }

        public static GameObject Prim(PrimitiveType t, Transform parent, Vector3 localPos, Vector3 scale, Color c, bool keepCollider = false, float gloss = 0.2f, float emission = 0f)
        {
            var g = GameObject.CreatePrimitive(t);
            if (!keepCollider) Object.Destroy(g.GetComponent<Collider>());
            g.transform.SetParent(parent, false);
            g.transform.localPosition = localPos;
            g.transform.localScale = scale;
            var r = g.GetComponent<Renderer>();
            r.sharedMaterial = Get(c, gloss, emission);
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
            return g;
        }
    }
}
