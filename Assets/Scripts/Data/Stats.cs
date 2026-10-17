using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    /// <summary>Итоговые характеристики персонажа: класс + уровень + таланты + путь + снаряжение.</summary>
    public class StatBlock
    {
        public readonly Dictionary<string, float> raw = new Dictionary<string, float>();
        public float MaxHp, MaxMp, Damage, DamageMult, SpellMult, AttackSpeed, MoveSpeed, Crit, CritMult, Armor, Regen, MpRegen, Leech, Cdr;

        public float Get(string k) => raw.TryGetValue(k, out var v) ? v : 0f;
        public void Add(string k, float v) { raw[k] = Get(k) + v; }
        public void Add(IEnumerable<StatMod> mods) { if (mods == null) return; foreach (var m in mods) Add(m.stat, m.value); }

        public static readonly Dictionary<string, string> Names = new Dictionary<string, string>
        {
            {"hp","к здоровью"},{"hp%","% к здоровью"},{"mp","к мане"},{"mp%","% к мане"},
            {"dmg","к урону"},{"dmg%","% к урону"},{"spell%","% к урону чар"},{"as%","% к скорости атаки"},
            {"ms%","% к скорости бега"},{"crit","% шанс крит. удара"},{"critdmg%","% к силе крит. удара"},
            {"armor","к броне"},{"armor%","% к броне"},{"regen","здоровья в сек."},{"mpregen","маны в сек."},
            {"leech%","% похищения жизни"},{"cdr%","% сокращения перезарядки"},
        };

        public static string Describe(StatMod m)
        {
            var name = Names.TryGetValue(m.stat, out var n) ? n : m.stat;
            var v = Mathf.Abs(m.value - Mathf.Round(m.value)) < 0.01f ? Mathf.RoundToInt(m.value).ToString() : m.value.ToString("0.#");
            return (m.value >= 0 ? "+" : "") + v + " " + name;
        }

        public static StatBlock Compute(CharacterData c)
        {
            var s = new StatBlock();
            var cls = ClassDefs.Get(c.classId);
            var tree = TalentTree.Instance;
            foreach (var id in c.talents) { var n = tree.Get(id); if (n != null) s.Add(n.mods); }
            var asc = AscendancyDefs.Get(c.ascendancy);
            if (asc != null) s.Add(asc.mods);
            float weaponDmg = 0, itemArmor = 0;
            foreach (var it in c.equipped)
            {
                if (it == null) continue;
                s.Add(it.mods);
                if (it.Slot == ItemSlot.Weapon) weaponDmg += it.baseValue; else itemArmor += it.baseValue;
            }
            s.Add("dmg%", (c.classLevel - 1) * 3f); // мастерство класса

            int L = c.level - 1;
            s.MaxHp = (cls.baseHp + cls.hpPerLevel * L + s.Get("hp")) * (1 + s.Get("hp%") / 100f);
            s.MaxMp = (cls.baseMp + cls.mpPerLevel * L + s.Get("mp")) * (1 + s.Get("mp%") / 100f);
            s.Damage = cls.baseDamage + cls.damagePerLevel * L + weaponDmg + s.Get("dmg");
            s.DamageMult = 1 + s.Get("dmg%") / 100f;
            s.SpellMult = 1 + s.Get("spell%") / 100f;
            s.AttackSpeed = Mathf.Max(0.3f, 1 + s.Get("as%") / 100f);
            s.MoveSpeed = 5.2f * Mathf.Clamp(1 + s.Get("ms%") / 100f, 0.5f, 2f);
            s.Crit = Mathf.Clamp(5 + s.Get("crit"), 0, 80) / 100f;
            s.CritMult = 1.5f + s.Get("critdmg%") / 100f;
            s.Armor = Mathf.Max(0, (5 + itemArmor + s.Get("armor")) * (1 + s.Get("armor%") / 100f));
            s.Regen = 0.5f + s.Get("regen");
            s.MpRegen = 2f + s.Get("mpregen");
            s.Leech = s.Get("leech%") / 100f;
            s.Cdr = Mathf.Clamp(s.Get("cdr%"), 0, 50) / 100f;
            return s;
        }

        public float DamageReduction => Armor / (Armor + 120f) * 0.8f;
    }
}
