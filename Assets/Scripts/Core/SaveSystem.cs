using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace RPG
{
    /// <summary>Сохранение персонажей в JSON-файлы на устройстве (Application.persistentDataPath/saves).</summary>
    public static class SaveSystem
    {
        public const int MaxSlots = 6;
        static string Dir => Path.Combine(Application.persistentDataPath, "saves");

        static string PathFor(string id) => Path.Combine(Dir, "char_" + id + ".json");

        public static List<CharacterData> LoadAll()
        {
            var list = new List<CharacterData>();
            try
            {
                if (!Directory.Exists(Dir)) return list;
                foreach (var f in Directory.GetFiles(Dir, "char_*.json"))
                {
                    try
                    {
                        var c = JsonUtility.FromJson<CharacterData>(File.ReadAllText(f));
                        if (c != null && !string.IsNullOrEmpty(c.id)) list.Add(c);
                    }
                    catch (Exception e) { Debug.LogWarning("Повреждённое сохранение " + f + ": " + e.Message); }
                }
            }
            catch (Exception e) { Debug.LogWarning(e); }
            list.Sort((a, b) => a.createdTicks.CompareTo(b.createdTicks));
            return list;
        }

        public static void Save(CharacterData c)
        {
            if (c == null) return;
            try
            {
                Directory.CreateDirectory(Dir);
                var tmp = PathFor(c.id) + ".tmp";
                File.WriteAllText(tmp, JsonUtility.ToJson(c));
                var dst = PathFor(c.id);
                if (File.Exists(dst)) File.Delete(dst);
                File.Move(tmp, dst);
            }
            catch (Exception e) { Debug.LogError("Ошибка сохранения: " + e); }
        }

        public static void Delete(string id)
        {
            try { var p = PathFor(id); if (File.Exists(p)) File.Delete(p); } catch (Exception e) { Debug.LogWarning(e); }
        }

        public static string NewId() => Guid.NewGuid().ToString("N").Substring(0, 12);
    }
}
