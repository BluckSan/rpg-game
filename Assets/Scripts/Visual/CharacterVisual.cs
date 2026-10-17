using UnityEngine;

namespace RPG
{
    /// <summary>Модель персонажа из примитивов + процедурная анимация (ходьба, удар, превращения).</summary>
    public class CharacterVisual : MonoBehaviour
    {
        public static readonly Color[] SkinColors =
        {
            new Color(1f,0.87f,0.77f), new Color(0.96f,0.78f,0.62f), new Color(0.85f,0.65f,0.47f),
            new Color(0.66f,0.46f,0.32f), new Color(0.45f,0.3f,0.2f), new Color(0.3f,0.2f,0.14f),
            new Color(0.6f,0.75f,0.6f) /* эльфийский зеленоватый */, new Color(0.7f,0.72f,0.85f) /* бледный */
        };
        public static readonly Color[] HairColors =
        {
            new Color(0.08f,0.06f,0.05f), new Color(0.35f,0.2f,0.1f), new Color(0.6f,0.4f,0.2f), new Color(0.95f,0.85f,0.55f),
            new Color(0.75f,0.25f,0.1f), new Color(0.9f,0.9f,0.92f), new Color(0.3f,0.4f,0.9f), new Color(0.8f,0.3f,0.6f)
        };
        public static readonly Color[] EyeColors =
        {
            new Color(0.3f,0.2f,0.1f), new Color(0.2f,0.45f,0.9f), new Color(0.25f,0.65f,0.3f),
            new Color(0.5f,0.5f,0.5f), new Color(0.85f,0.65f,0.1f), new Color(0.8f,0.1f,0.1f)
        };
        public static readonly string[] HairStyleNames = { "Короткая", "Ёжик", "Длинная", "Хвост", "Ирокез", "Лысый" };
        public static readonly string[] FaceNames = { "Обычное", "Острое", "Борода", "Шрам" };

        Transform root, legL, legR, armL, armR, body, orbit;
        float walkPhase, attackT = -1, hitFlash;
        Vector3 lastPos;
        public float speedOverride = -1;
        bool beast;

        public void Build(Appearance a, string classId, string ascendancy)
        {
            if (root != null) Destroy(root.gameObject);
            root = new GameObject("Model").transform;
            root.SetParent(transform, false);
            beast = ascendancy == "druid";
            var cls = ClassDefs.Get(classId);
            var asc = AscendancyDefs.Get(ascendancy);

            Color skin = SkinColors[Mathf.Clamp(a.skin, 0, SkinColors.Length - 1)];
            Color hair = HairColors[Mathf.Clamp(a.hairColor, 0, HairColors.Length - 1)];
            Color eye = EyeColors[Mathf.Clamp(a.eyeColor, 0, EyeColors.Length - 1)];
            Color cloth = cls.color * 0.8f; cloth.a = 1;
            Color pants = new Color(0.25f, 0.22f, 0.2f);
            float eyeGlow = 0f;
            if (ascendancy == "necromancer") { skin = Color.Lerp(skin, new Color(0.8f, 0.8f, 0.85f), 0.6f); cloth = new Color(0.2f, 0.1f, 0.3f); eye = new Color(0.6f, 1f, 0.6f); eyeGlow = 2f; }
            if (ascendancy == "shadow") { cloth = new Color(0.1f, 0.1f, 0.14f); pants = cloth; eye = new Color(0.7f, 0.3f, 1f); eyeGlow = 2f; }
            if (ascendancy == "berserker") { eye = new Color(1f, 0.15f, 0.05f); eyeGlow = 2.5f; }
            if (ascendancy == "paladin") { cloth = new Color(0.85f, 0.85f, 0.9f); }
            if (ascendancy == "elementalist") { cloth = new Color(0.15f, 0.3f, 0.7f); eyeGlow = 1.5f; eye = new Color(0.5f, 0.9f, 1f); }

            float h = Mathf.Clamp(a.height, 0.8f, 1.2f);
            float b = Mathf.Clamp(a.build, 0.75f, 1.3f);
            bool female = a.gender == 1;
            float shoulder = (female ? 0.42f : 0.5f) * b;
            float hip = (female ? 0.4f : 0.36f) * b;
            float scale = h * (ascendancy == "berserker" ? 1.12f : 1f);
            root.localScale = Vector3.one * scale;

            if (beast) { BuildBeast(hair, eye); return; }

            body = new GameObject("Body").transform; body.SetParent(root, false);
            // ноги
            legL = Pivot("LegL", new Vector3(-hip * 0.4f, 0.9f, 0)); legR = Pivot("LegR", new Vector3(hip * 0.4f, 0.9f, 0));
            foreach (var leg in new[] { legL, legR })
            {
                Mat.Prim(PrimitiveType.Capsule, leg, new Vector3(0, -0.45f, 0), new Vector3(0.2f * b, 0.45f, 0.2f * b), pants);
                Mat.Prim(PrimitiveType.Cube, leg, new Vector3(0, -0.86f, 0.06f), new Vector3(0.2f * b, 0.1f, 0.3f), new Color(0.3f, 0.2f, 0.12f));
            }
            // таз и торс
            Mat.Prim(PrimitiveType.Cube, body, new Vector3(0, 0.95f, 0), new Vector3(hip, 0.22f, 0.26f * b), pants);
            Mat.Prim(PrimitiveType.Capsule, body, new Vector3(0, 1.27f, 0), new Vector3(shoulder, 0.36f, 0.28f * b), cloth);
            if (female) Mat.Prim(PrimitiveType.Sphere, body, new Vector3(0, 1.36f, 0.09f), new Vector3(shoulder * 0.75f, 0.17f, 0.15f), cloth);
            Mat.Prim(PrimitiveType.Cube, body, new Vector3(0, 1.08f, 0), new Vector3(shoulder * 0.95f, 0.07f, 0.3f * b), new Color(0.35f, 0.22f, 0.1f)); // пояс
            // руки
            armL = Pivot("ArmL", new Vector3(-shoulder * 0.62f, 1.52f, 0)); armR = Pivot("ArmR", new Vector3(shoulder * 0.62f, 1.52f, 0));
            foreach (var arm in new[] { armL, armR })
            {
                Mat.Prim(PrimitiveType.Capsule, arm, new Vector3(0, -0.3f, 0), new Vector3(0.15f * b, 0.32f, 0.15f * b), cloth);
                Mat.Prim(PrimitiveType.Sphere, arm, new Vector3(0, -0.64f, 0), Vector3.one * 0.13f, skin);
            }
            // голова
            var head = new GameObject("Head").transform; head.SetParent(body, false); head.localPosition = new Vector3(0, 1.84f, 0);
            Mat.Prim(PrimitiveType.Cylinder, body, new Vector3(0, 1.66f, 0), new Vector3(0.13f, 0.06f, 0.13f), skin);
            float faceW = a.face == 1 ? 0.3f : 0.34f;
            Mat.Prim(PrimitiveType.Sphere, head, Vector3.zero, new Vector3(faceW, 0.38f, 0.34f), skin, false, 0.3f);
            Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, -0.02f, 0.17f), new Vector3(0.06f, 0.08f, 0.06f), skin * 0.95f); // нос
            foreach (var sx in new[] { -0.075f, 0.075f })
            {
                Mat.Prim(PrimitiveType.Sphere, head, new Vector3(sx, 0.04f, 0.145f), new Vector3(0.075f, 0.06f, 0.04f), Color.white);
                Mat.Prim(PrimitiveType.Sphere, head, new Vector3(sx, 0.04f, 0.162f), new Vector3(0.04f, 0.045f, 0.02f), eye, false, 0.8f, eyeGlow);
                Mat.Prim(PrimitiveType.Cube, head, new Vector3(sx, 0.11f, 0.15f), new Vector3(0.08f, 0.015f, 0.02f), hair); // брови
            }
            if (a.face == 2 && !female) Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, -0.13f, 0.08f), new Vector3(0.28f, 0.2f, 0.24f), hair);
            if (a.face == 3) Mat.Prim(PrimitiveType.Cube, head, new Vector3(0.08f, 0.0f, 0.165f), new Vector3(0.015f, 0.14f, 0.01f), new Color(0.6f, 0.25f, 0.25f));
            BuildHair(head, a.hairStyle, hair, female);

            BuildWeapon(classId);
            BuildAscendancyExtras(asc, head);
        }

        Transform Pivot(string n, Vector3 p)
        {
            var t = new GameObject(n).transform; t.SetParent(body, false); t.localPosition = p; return t;
        }

        void BuildHair(Transform head, int style, Color c, bool female)
        {
            switch (style)
            {
                case 0: Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, 0.07f, -0.02f), new Vector3(0.37f, 0.3f, 0.37f), c); break;
                case 1: Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, 0.1f, -0.01f), new Vector3(0.35f, 0.24f, 0.35f), c); break;
                case 2:
                    Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, 0.07f, -0.02f), new Vector3(0.38f, 0.31f, 0.38f), c);
                    Mat.Prim(PrimitiveType.Cube, head, new Vector3(0, -0.2f, -0.12f), new Vector3(0.36f, 0.5f, 0.14f), c);
                    break;
                case 3:
                    Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, 0.07f, -0.02f), new Vector3(0.37f, 0.3f, 0.37f), c);
                    Mat.Prim(PrimitiveType.Capsule, head, new Vector3(0, -0.12f, -0.22f), new Vector3(0.1f, 0.22f, 0.1f), c);
                    break;
                case 4: Mat.Prim(PrimitiveType.Cube, head, new Vector3(0, 0.2f, -0.02f), new Vector3(0.07f, 0.18f, 0.36f), c); break;
                default: break; // лысый
            }
        }

        void BuildWeapon(string classId)
        {
            var hand = new GameObject("Weapon").transform; hand.SetParent(armR, false); hand.localPosition = new Vector3(0, -0.66f, 0.05f);
            switch (classId)
            {
                case "archer":
                    hand.SetParent(armL, false); hand.localPosition = new Vector3(0, -0.66f, 0.05f);
                    Mat.Prim(PrimitiveType.Cylinder, hand, new Vector3(0, 0, 0.05f), new Vector3(0.04f, 0.5f, 0.04f), new Color(0.45f, 0.28f, 0.12f));
                    Mat.Prim(PrimitiveType.Cylinder, hand, new Vector3(0, 0, -0.05f), new Vector3(0.008f, 0.48f, 0.008f), Color.white);
                    break;
                case "mage":
                    Mat.Prim(PrimitiveType.Cylinder, hand, new Vector3(0, 0.25f, 0.05f), new Vector3(0.05f, 0.75f, 0.05f), new Color(0.35f, 0.22f, 0.1f));
                    Mat.Prim(PrimitiveType.Sphere, hand, new Vector3(0, 1.02f, 0.05f), Vector3.one * 0.16f, new Color(0.4f, 0.7f, 1f), false, 0.9f, 2f);
                    break;
                default:
                    Mat.Prim(PrimitiveType.Cube, hand, new Vector3(0, 0, 0.42f), new Vector3(0.06f, 0.03f, 0.8f), new Color(0.75f, 0.77f, 0.8f), false, 0.8f);
                    Mat.Prim(PrimitiveType.Cube, hand, new Vector3(0, 0, 0.02f), new Vector3(0.22f, 0.05f, 0.05f), new Color(0.5f, 0.35f, 0.1f));
                    break;
            }
        }

        void BuildAscendancyExtras(AscendancyDef asc, Transform head)
        {
            if (asc == null) return;
            switch (asc.id)
            {
                case "berserker":
                    foreach (var s in new[] { -1, 1 })
                    {
                        var sp = Mat.Prim(PrimitiveType.Cube, body, new Vector3(s * 0.3f, 1.62f, 0), new Vector3(0.08f, 0.25f, 0.08f), new Color(0.4f, 0.05f, 0.05f));
                        sp.transform.localRotation = Quaternion.Euler(0, 0, -s * 30);
                    }
                    break;
                case "paladin":
                    foreach (var s in new[] { -1, 1 })
                        Mat.Prim(PrimitiveType.Sphere, body, new Vector3(s * 0.3f, 1.55f, 0), new Vector3(0.28f, 0.16f, 0.3f), new Color(1f, 0.8f, 0.25f), false, 0.9f);
                    var halo = Mat.Prim(PrimitiveType.Cylinder, head, new Vector3(0, 0.33f, 0), new Vector3(0.36f, 0.01f, 0.36f), new Color(1f, 0.9f, 0.4f), false, 1f, 3f);
                    break;
                case "elementalist":
                case "necromancer":
                case "shadow":
                    orbit = new GameObject("Orbit").transform; orbit.SetParent(root, false); orbit.localPosition = new Vector3(0, 1.4f, 0);
                    Color[] cols = asc.id == "elementalist"
                        ? new[] { new Color(1f, 0.4f, 0.1f), new Color(0.4f, 0.8f, 1f), new Color(1f, 1f, 0.4f) }
                        : asc.id == "necromancer" ? new[] { new Color(0.9f, 0.9f, 0.8f), new Color(0.9f, 0.9f, 0.8f) }
                        : new[] { new Color(0.15f, 0.1f, 0.2f), new Color(0.2f, 0.1f, 0.3f), new Color(0.1f, 0.05f, 0.15f), new Color(0.2f, 0.1f, 0.3f) };
                    for (int i = 0; i < cols.Length; i++)
                    {
                        float ang = i * Mathf.PI * 2 / cols.Length;
                        float r = asc.id == "shadow" ? 0.35f : 0.75f;
                        var o = Mat.Prim(PrimitiveType.Sphere, orbit, new Vector3(Mathf.Cos(ang) * r, asc.id == "shadow" ? -0.8f + i * 0.4f : 0.3f, Mathf.Sin(ang) * r),
                            Vector3.one * (asc.id == "shadow" ? 0.5f : 0.18f), cols[i], false, 0.5f, asc.id == "shadow" ? 0 : 2f);
                        if (asc.id == "shadow") o.GetComponent<Renderer>().sharedMaterial = Mat.Transparent(new Color(0.1f, 0.05f, 0.15f, 0.45f));
                    }
                    break;
            }
        }

        void BuildBeast(Color fur, Color eye)
        {
            fur = Color.Lerp(fur, new Color(0.35f, 0.22f, 0.12f), 0.6f);
            body = new GameObject("Body").transform; body.SetParent(root, false);
            root.localScale *= 1.25f;
            Mat.Prim(PrimitiveType.Capsule, body, new Vector3(0, 0.95f, 0), new Vector3(0.85f, 0.75f, 0.85f), fur).transform.localRotation = Quaternion.Euler(90, 0, 0);
            var head = new GameObject("Head").transform; head.SetParent(body, false); head.localPosition = new Vector3(0, 1.25f, 0.8f);
            Mat.Prim(PrimitiveType.Sphere, head, Vector3.zero, new Vector3(0.55f, 0.5f, 0.55f), fur);
            Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, -0.08f, 0.25f), new Vector3(0.28f, 0.22f, 0.3f), fur * 1.3f);
            Mat.Prim(PrimitiveType.Sphere, head, new Vector3(0, -0.02f, 0.4f), Vector3.one * 0.08f, Color.black);
            foreach (var s in new[] { -1, 1 })
            {
                Mat.Prim(PrimitiveType.Sphere, head, new Vector3(s * 0.2f, 0.25f, -0.05f), new Vector3(0.15f, 0.15f, 0.08f), fur);
                Mat.Prim(PrimitiveType.Sphere, head, new Vector3(s * 0.12f, 0.08f, 0.24f), Vector3.one * 0.06f, new Color(0.9f, 0.9f, 0.3f), false, 0.8f, 2f);
            }
            legL = Pivot("LegL", new Vector3(-0.3f, 0.7f, 0.45f)); legR = Pivot("LegR", new Vector3(0.3f, 0.7f, 0.45f));
            armL = Pivot("LegBL", new Vector3(-0.3f, 0.7f, -0.45f)); armR = Pivot("LegBR", new Vector3(0.3f, 0.7f, -0.45f));
            foreach (var l in new[] { legL, legR, armL, armR })
                Mat.Prim(PrimitiveType.Capsule, l, new Vector3(0, -0.35f, 0), new Vector3(0.28f, 0.38f, 0.28f), fur * 0.9f);
        }

        public void PlayAttack() { attackT = 0; }
        public void Flash() { hitFlash = 0.12f; }

        void LateUpdate()
        {
            if (root == null) return;
            var p = transform.position;
            float spd = speedOverride >= 0 ? speedOverride : (new Vector3(p.x - lastPos.x, 0, p.z - lastPos.z).magnitude / Mathf.Max(Time.deltaTime, 0.0001f));
            lastPos = p;
            float moving = Mathf.Clamp01(spd / 4f);
            walkPhase += Time.deltaTime * (4f + spd * 1.6f);
            float swing = Mathf.Sin(walkPhase) * 38f * moving;
            if (legL) legL.localRotation = Quaternion.Euler(swing, 0, 0);
            if (legR) legR.localRotation = Quaternion.Euler(-swing, 0, 0);
            if (beast)
            {
                if (armL) armL.localRotation = Quaternion.Euler(-swing, 0, 0);
                if (armR) armR.localRotation = Quaternion.Euler(swing, 0, 0);
            }
            else
            {
                if (armL) armL.localRotation = Quaternion.Euler(-swing * 0.7f, 0, -6);
                if (armR)
                {
                    if (attackT >= 0)
                    {
                        attackT += Time.deltaTime / 0.3f;
                        float k = attackT < 0.4f ? attackT / 0.4f : 1 - (attackT - 0.4f) / 0.6f;
                        armR.localRotation = Quaternion.Euler(-150f * Mathf.Clamp01(k), 0, 6);
                        if (attackT >= 1) attackT = -1;
                    }
                    else armR.localRotation = Quaternion.Euler(swing * 0.7f, 0, 6);
                }
            }
            if (body) body.localPosition = new Vector3(0, Mathf.Abs(Mathf.Sin(walkPhase)) * 0.05f * moving + Mathf.Sin(Time.time * 2f) * 0.01f, 0);
            if (orbit) orbit.localRotation = Quaternion.Euler(0, Time.time * 90f, 0);
            if (hitFlash > 0)
            {
                hitFlash -= Time.deltaTime;
                root.localScale = Vector3.one * root.localScale.x; // no-op, сохраняет масштаб
            }
        }
    }
}
