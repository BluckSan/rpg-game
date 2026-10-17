using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    public static class LootGenerator
    {
        public static readonly string[] RarityNames = { "Обычный", "Магический", "Редкий", "Уникальный" };
        public static readonly Color[] RarityColors =
        {
            new Color(0.9f,0.9f,0.9f), new Color(0.4f,0.6f,1f), new Color(1f,0.9f,0.3f), new Color(1f,0.5f,0.1f)
        };
        public static readonly string[] SlotNames = { "Оружие", "Броня", "Шлем", "Кольцо" };

        static readonly string[] armorBases = { "Кожаная куртка", "Кольчуга", "Латный доспех" };
        static readonly string[] helmBases = { "Капюшон", "Железный шлем", "Рогатый шлем" };
        static readonly string[] ringBases = { "Медное кольцо", "Серебряное кольцо", "Кольцо с рубином" };
        static readonly string[] prefixes = { "Острый", "Крепкий", "Быстрый", "Древний", "Пылающий", "Ледяной", "Кровавый", "Святой", "Теневой" };
        static readonly string[] uniques = { "Клык Тролля", "Сердце долины", "Пепельный венец", "Шёпот бури" };

        static readonly (string stat, float min, float max)[] affixPool =
        {
            ("hp",10,40),("mp",10,35),("dmg%",4,15),("as%",3,10),("ms%",2,8),("crit",1,5),
            ("critdmg%",8,25),("armor",8,30),("regen",0.5f,2.5f),("spell%",5,16),("leech%",0.3f,1.5f),("cdr%",2,6)
        };

        static string WeaponBase(string classId, int tier)
        {
            switch (classId)
            {
                case "archer": return new[] { "Короткий лук", "Длинный лук", "Составной лук" }[tier];
                case "mage": return new[] { "Посох", "Жезл чародея", "Посох архимага" }[tier];
                default: return new[] { "Меч", "Боевой топор", "Двуручный клинок" }[tier];
            }
        }

        public static ItemData StarterWeapon(ClassDef cls) => new ItemData
        {
            uid = SaveSystem.NewId(), name = cls.weaponName, slot = (int)ItemSlot.Weapon, rarity = 0, itemLevel = 1, baseValue = 3
        };

        public static ItemData Roll(int itemLevel, string classId, float rarityBonus = 0f)
        {
            var it = new ItemData { uid = SaveSystem.NewId(), itemLevel = itemLevel, slot = Random.Range(0, 4) };
            float r = Random.value - rarityBonus;
            it.rarity = r < 0.02f ? 3 : r < 0.14f ? 2 : r < 0.45f ? 1 : 0;
            int tier = Mathf.Clamp(itemLevel / 4, 0, 2);
            string baseName;
            switch (it.Slot)
            {
                case ItemSlot.Weapon: baseName = WeaponBase(classId, tier); it.baseValue = 3 + itemLevel * 1.6f + Random.Range(0f, 3f); break;
                case ItemSlot.Armor: baseName = armorBases[tier]; it.baseValue = 6 + itemLevel * 3f + Random.Range(0f, 5f); break;
                case ItemSlot.Helmet: baseName = helmBases[tier]; it.baseValue = 3 + itemLevel * 1.5f + Random.Range(0f, 3f); break;
                default: baseName = ringBases[tier]; it.baseValue = 0; break;
            }
            it.baseValue = Mathf.Round(it.baseValue);
            int affixes = it.rarity == 0 ? (it.Slot == ItemSlot.Ring ? 1 : 0) : it.rarity == 1 ? Random.Range(1, 3) : it.rarity == 2 ? Random.Range(3, 5) : 5;
            var used = new HashSet<int>();
            float scale = 1f + itemLevel * 0.08f;
            for (int i = 0; i < affixes; i++)
            {
                int k; int guard = 0;
                do { k = Random.Range(0, affixPool.Length); } while (used.Contains(k) && guard++ < 20);
                used.Add(k);
                var a = affixPool[k];
                float v = Random.Range(a.min, a.max) * scale * (it.rarity == 3 ? 1.5f : 1f);
                v = v >= 5 ? Mathf.Round(v) : Mathf.Round(v * 10) / 10f;
                it.mods.Add(new StatMod(a.stat, v));
            }
            if (it.rarity == 3) { it.name = uniques[Random.Range(0, uniques.Length)]; it.baseValue *= 1.3f; it.baseValue = Mathf.Round(it.baseValue); }
            else if (it.rarity >= 1) it.name = prefixes[Random.Range(0, prefixes.Length)] + " " + baseName.ToLowerInvariant();
            else it.name = baseName;
            return it;
        }

        public static string Describe(ItemData it)
        {
            var sb = new System.Text.StringBuilder();
            sb.Append(SlotNames[it.slot]).Append(" · ").Append(RarityNames[it.rarity]).Append(" · ур. ").Append(it.itemLevel).Append('\n');
            if (it.Slot == ItemSlot.Weapon) sb.Append("Урон: +").Append(it.baseValue).Append('\n');
            else if (it.baseValue > 0) sb.Append("Броня: +").Append(it.baseValue).Append('\n');
            foreach (var m in it.mods) sb.Append(StatBlock.Describe(m)).Append('\n');
            return sb.ToString().TrimEnd();
        }
    }
}
