using System;
using System.Collections.Generic;
using UnityEngine;

namespace RPG
{
    [Serializable]
    public class TalentNode
    {
        public int id;
        public string name;
        public string type;     // start | minor | notable | keystone
        public string region;   // id региона (пути) или пусто
        public string classId;  // для стартовых узлов
        public float x, y;
        public List<StatMod> mods = new List<StatMod>();
        public List<int> links = new List<int>();
    }

    [Serializable]
    public class TalentRegion
    {
        public string id, name, color;
        public Color Color { get { ColorUtility.TryParseHtmlString(color, out var c); return c; } }
    }

    [Serializable]
    public class TalentTreeFile
    {
        public int version;
        public List<TalentRegion> regions = new List<TalentRegion>();
        public List<TalentNode> nodes = new List<TalentNode>();
    }

    /// <summary>
    /// Дерево пассивных талантов. Данные лежат в Resources/Talents/talent_tree.json
    /// (генерируется tools/gen_talent_tree.py, можно править вручную).
    /// </summary>
    public class TalentTree
    {
        static TalentTree instance;
        public static TalentTree Instance => instance ??= Load();

        public TalentTreeFile data;
        readonly Dictionary<int, TalentNode> byId = new Dictionary<int, TalentNode>();

        static TalentTree Load()
        {
            var t = new TalentTree();
            var ta = Resources.Load<TextAsset>("Talents/talent_tree");
            t.data = ta != null ? JsonUtility.FromJson<TalentTreeFile>(ta.text) : new TalentTreeFile();
            foreach (var n in t.data.nodes) t.byId[n.id] = n;
            return t;
        }

        public TalentNode Get(int id) => byId.TryGetValue(id, out var n) ? n : null;
        public IEnumerable<TalentNode> Nodes => data.nodes;
        public TalentRegion Region(string id) => data.regions.Find(r => r.id == id);

        public int StartNodeFor(string classId)
        {
            var n = data.nodes.Find(x => x.type == "start" && x.classId == classId);
            return n != null ? n.id : 0;
        }

        public bool CanAllocate(CharacterData c, int id)
        {
            var n = Get(id);
            if (n == null || n.type == "start" || c.talents.Contains(id)) return false;
            if (c.FreeTalentPoints <= 0) return false;
            foreach (var l in n.links) if (c.talents.Contains(l)) return true;
            return false;
        }

        public bool Allocate(CharacterData c, int id)
        {
            if (!CanAllocate(c, id)) return false;
            c.talents.Add(id);
            return true;
        }

        public void ResetAll(CharacterData c)
        {
            c.talents.Clear();
            c.talents.Add(StartNodeFor(c.classId));
            c.ascendancy = "";
        }

        public int PointsInRegion(CharacterData c, string region)
        {
            int k = 0;
            foreach (var id in c.talents) { var n = Get(id); if (n != null && n.region == region) k++; }
            return k;
        }

        public TalentNode KeystoneOf(string region) => data.nodes.Find(n => n.type == "keystone" && n.region == region);
    }
}
