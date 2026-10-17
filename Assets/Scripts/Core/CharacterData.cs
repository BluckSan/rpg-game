using System;
using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    [Serializable]
    public class Appearance
    {
        public int gender;          // 0 = мужской, 1 = женский
        public float height = 1f;   // 0.85 .. 1.15
        public float build = 1f;    // 0.8 .. 1.25 (телосложение)
        public int skin;            // индекс палитры
        public int face;            // 0..3 (форма лица/борода)
        public int hairStyle;       // 0..5
        public int hairColor;
        public int eyeColor;
    }

    [Serializable]
    public class StatMod
    {
        public string stat;
        public float value;
        public StatMod() { }
        public StatMod(string s, float v) { stat = s; value = v; }
    }

    public enum ItemSlot { Weapon = 0, Armor = 1, Helmet = 2, Ring = 3 }
    public enum Rarity { Common = 0, Magic = 1, Rare = 2, Unique = 3 }

    [Serializable]
    public class ItemData
    {
        public string uid;
        public string name;
        public int slot;
        public int rarity;
        public int itemLevel;
        public float baseValue;     // урон оружия / броня
        public List<StatMod> mods = new List<StatMod>();
        public ItemSlot Slot => (ItemSlot)slot;
        public Rarity Rarity => (Rarity)rarity;
    }

    [Serializable]
    public class ZoneState
    {
        public string zoneId;
        public List<string> flags = new List<string>(); // например "boss_troll_killed"
    }

    [Serializable]
    public class CharacterData
    {
        public string id;
        public string name;
        public string classId = "warrior";
        public Appearance look = new Appearance();

        public int level = 1;
        public long xp;
        public int classLevel = 1;
        public long classXp;
        public List<int> talents = new List<int>();
        public string ascendancy = "";

        public int gold;
        public int potions = 3;
        public List<ItemData> inventory = new List<ItemData>();
        public List<ItemData> equipped = new List<ItemData>();

        public string zoneId = ZoneRegistry.StarterZone;
        public bool hasPosition;
        public float px, py, pz;
        public List<ZoneState> zones = new List<ZoneState>();

        public long createdTicks;
        public float playSeconds;
        public int kills;

        public ItemData GetEquipped(ItemSlot s) => equipped.Find(i => i != null && i.slot == (int)s);

        public ZoneState GetZone(string zid)
        {
            var z = zones.Find(x => x.zoneId == zid);
            if (z == null) { z = new ZoneState { zoneId = zid }; zones.Add(z); }
            return z;
        }

        public static long XpToNext(int level) => (long)(60 * Mathf.Pow(level, 1.6f));
        public static long ClassXpToNext(int classLevel) => (long)(100 * Mathf.Pow(classLevel, 1.5f));

        public int TotalTalentPoints => (level - 1) + 2 + (classLevel - 1) / 2; // 2 стартовых очка
        public int FreeTalentPoints => TotalTalentPoints - Mathf.Max(0, talents.Count - 1); // стартовый узел бесплатный
    }
}
