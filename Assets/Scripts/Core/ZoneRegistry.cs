using System.Collections.Generic;

namespace RPG
{
    public class ZoneDef
    {
        public string id;
        public string displayName;
        public string sceneName;
        public bool available;   // false = ещё не реализована
        public int minLevel;
    }

    /// <summary>
    /// Реестр зон. Чтобы добавить глобальную карту: создать сцену "GlobalMap" с ZoneBootstrap(zoneId="global"),
    /// добавить её в Build Settings (ProjectSetup.Scenes) и поставить available = true.
    /// </summary>
    public static class ZoneRegistry
    {
        public const string StarterZone = "starter";
        public const string GlobalZone = "global";

        static readonly List<ZoneDef> zones = new List<ZoneDef>
        {
            new ZoneDef { id = StarterZone, displayName = "Пепельная долина", sceneName = "StarterZone", available = true, minLevel = 1 },
            new ZoneDef { id = GlobalZone,  displayName = "Земли Эфира",      sceneName = "GlobalMap",   available = false, minLevel = 10 },
        };

        public static ZoneDef Get(string id) => zones.Find(z => z.id == id);
        public static IReadOnlyList<ZoneDef> All => zones;
    }
}
