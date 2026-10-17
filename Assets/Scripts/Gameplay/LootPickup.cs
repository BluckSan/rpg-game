using UnityEngine;

namespace RPG
{
    public enum LootType { Gold, Potion, Item }

    /// <summary>Добыча на земле. Подбирается автоматически, когда игрок рядом.</summary>
    public class LootPickup : MonoBehaviour
    {
        LootType type; int amount; ItemData item;
        float age;

        public static void DropFor(Enemy e)
        {
            var pos = e.transform.position;
            int lvl = e.level;
            Spawn(pos + Rand(), LootType.Gold, Mathf.RoundToInt(Random.Range(2, 6) * (1 + lvl * 0.5f) * (e.def.boss ? 10 : 1)), null);
            if (Random.value < (e.def.boss ? 1f : 0.1f)) Spawn(pos + Rand(), LootType.Potion, 1, null);
            int items = e.def.boss ? 3 : (Random.value < 0.28f ? 1 : 0);
            var classId = PlayerCharacter.Instance != null ? PlayerCharacter.Instance.Data.classId : "warrior";
            for (int i = 0; i < items; i++)
                Spawn(pos + Rand(), LootType.Item, 1, LootGenerator.Roll(lvl, classId, e.def.boss ? 0.3f : 0f));
        }

        static Vector3 Rand() { var r = Random.insideUnitCircle * 1.2f; return new Vector3(r.x, 0, r.y); }

        public static LootPickup Spawn(Vector3 pos, LootType t, int amount, ItemData item)
        {
            var go = new GameObject("Loot_" + t);
            go.transform.position = new Vector3(pos.x, 0, pos.z);
            var l = go.AddComponent<LootPickup>();
            l.type = t; l.amount = amount; l.item = item;
            var holder = new GameObject("Vis").transform; holder.SetParent(go.transform, false); holder.localPosition = Vector3.up * 0.4f;
            Color c;
            switch (t)
            {
                case LootType.Gold:
                    c = new Color(1f, 0.82f, 0.2f);
                    Mat.Prim(PrimitiveType.Cylinder, holder, Vector3.zero, new Vector3(0.35f, 0.04f, 0.35f), c, false, 0.9f, 0.6f).transform.localRotation = Quaternion.Euler(90, 0, 0);
                    break;
                case LootType.Potion:
                    c = new Color(0.9f, 0.15f, 0.25f);
                    Mat.Prim(PrimitiveType.Sphere, holder, Vector3.zero, Vector3.one * 0.35f, c, false, 0.9f, 1f);
                    Mat.Prim(PrimitiveType.Cylinder, holder, new Vector3(0, 0.22f, 0), new Vector3(0.1f, 0.08f, 0.1f), new Color(0.6f, 0.4f, 0.2f));
                    break;
                default:
                    c = LootGenerator.RarityColors[item.rarity];
                    Mat.Prim(PrimitiveType.Cube, holder, Vector3.zero, new Vector3(0.45f, 0.45f, 0.45f), c, false, 0.6f, item.rarity > 0 ? 1.2f : 0.2f).transform.localRotation = Quaternion.Euler(45, 0, 45);
                    if (item.rarity > 0)
                    {
                        var beam = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                        Destroy(beam.GetComponent<Collider>());
                        beam.transform.SetParent(go.transform, false);
                        beam.transform.localPosition = Vector3.up * 2.5f; beam.transform.localScale = new Vector3(0.12f, 2.5f, 0.12f);
                        beam.GetComponent<Renderer>().sharedMaterial = Mat.Transparent(new Color(c.r, c.g, c.b, 0.35f));
                    }
                    break;
            }
            var sp = holder.gameObject.AddComponent<Spin>(); sp.speed = new Vector3(0, 120, 0); sp.bob = 0.1f;
            return l;
        }

        void Update()
        {
            age += Time.deltaTime;
            var pc = PlayerCharacter.Instance;
            if (pc == null || pc.Dead || age < 0.4f) return;
            var d = pc.transform.position - transform.position; d.y = 0;
            if (d.magnitude > 2.0f) return;
            var data = pc.Data;
            switch (type)
            {
                case LootType.Gold:
                    data.gold += amount; HUD.Instance?.Pickup($"+{amount} золота", new Color(1f, 0.85f, 0.3f)); break;
                case LootType.Potion:
                    data.potions += amount; HUD.Instance?.Pickup("+1 зелье лечения", new Color(1f, 0.4f, 0.4f)); break;
                case LootType.Item:
                    if (data.inventory.Count >= GameManager.InventorySize) { Toast.Show("Инвентарь полон!", 1.5f); age = -2f; return; }
                    data.inventory.Add(item);
                    HUD.Instance?.Pickup(item.name, LootGenerator.RarityColors[item.rarity]);
                    break;
            }
            Destroy(gameObject);
        }
    }
}
