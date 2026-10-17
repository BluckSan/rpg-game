using UnityEngine;

namespace RPG
{
    /// <summary>Простые эффекты из примитивов: вспышки, кольца, лучи.</summary>
    public static class FX
    {
        public static void Burst(Vector3 pos, float radius, Color c, float duration = 0.35f)
        {
            var g = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            Object.Destroy(g.GetComponent<Collider>());
            g.transform.position = pos;
            g.GetComponent<Renderer>().sharedMaterial = Mat.Transparent(new Color(c.r, c.g, c.b, 0.45f));
            g.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            g.AddComponent<FXGrow>().Init(radius * 2f, duration);
        }

        public static void Ring(Vector3 pos, float radius, Color c, float duration = 0.4f)
        {
            var g = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            Object.Destroy(g.GetComponent<Collider>());
            g.transform.position = pos + Vector3.up * 0.05f;
            g.GetComponent<Renderer>().sharedMaterial = Mat.Transparent(new Color(c.r, c.g, c.b, 0.4f));
            g.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            g.AddComponent<FXGrow>().Init(radius * 2f, duration, true);
        }

        /// <summary>Предупреждающий круг на земле (атаки босса).</summary>
        public static GameObject Telegraph(Vector3 pos, float radius, float duration)
        {
            var g = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            Object.Destroy(g.GetComponent<Collider>());
            g.transform.position = new Vector3(pos.x, 0.03f, pos.z);
            g.transform.localScale = new Vector3(radius * 2, 0.01f, radius * 2);
            g.GetComponent<Renderer>().sharedMaterial = Mat.Transparent(new Color(1f, 0.1f, 0.05f, 0.35f));
            Object.Destroy(g, duration);
            return g;
        }
    }

    public class FXGrow : MonoBehaviour
    {
        float size, dur, t; bool flat;
        public void Init(float s, float d, bool isFlat = false) { size = s; dur = d; flat = isFlat; Update(); }
        void Update()
        {
            t += Time.deltaTime;
            float k = Mathf.Clamp01(t / dur);
            float s = Mathf.Lerp(0.2f, size, 1 - (1 - k) * (1 - k));
            transform.localScale = flat ? new Vector3(s, 0.02f, s) : Vector3.one * s;
            if (t >= dur) Destroy(gameObject);
        }
    }

    public class Spin : MonoBehaviour
    {
        public Vector3 speed = new Vector3(0, 90, 0);
        public float bob;
        Vector3 start;
        void Start() { start = transform.localPosition; }
        void Update()
        {
            transform.Rotate(speed * Time.deltaTime, Space.Self);
            if (bob > 0) transform.localPosition = start + Vector3.up * Mathf.Sin(Time.time * 2f) * bob;
        }
    }
}
