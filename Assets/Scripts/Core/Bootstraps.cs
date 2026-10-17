using UnityEngine;

namespace RPG
{
    /// <summary>Точка входа сцены главного меню.</summary>
    public class MainMenuBootstrap : MonoBehaviour
    {
        void Start()
        {
            Application.targetFrameRate = 60;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            new GameObject("MainMenu").AddComponent<MainMenuUI>();
        }
    }

    /// <summary>Точка входа игровой зоны. zoneId определяет, какой строитель мира использовать.</summary>
    public class ZoneBootstrap : MonoBehaviour
    {
        public string zoneId = ZoneRegistry.StarterZone;

        void Start()
        {
            Application.targetFrameRate = 60;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            if (GameSession.Current == null)
            {
                // запуск сцены напрямую из редактора — тестовый персонаж
                var list = SaveSystem.LoadAll();
                GameSession.Current = list.Count > 0 ? list[0] : CharacterFactory.CreateDefault("Тестовый герой", "warrior");
            }
            var c = GameSession.Current;
            c.zoneId = zoneId;
            QualitySettings.shadows = PlayerPrefs.GetInt("shadows", 1) == 1 ? ShadowQuality.All : ShadowQuality.Disable;
            var world = new GameObject("World");
            if (zoneId == ZoneRegistry.StarterZone) world.AddComponent<StarterZoneBuilder>().Build();
            new GameObject("Game").AddComponent<GameManager>().Init(c);
        }
    }

    public static class CharacterFactory
    {
        public static CharacterData CreateDefault(string name, string classId)
        {
            var c = new CharacterData
            {
                id = SaveSystem.NewId(), name = name, classId = classId,
                createdTicks = System.DateTime.UtcNow.Ticks
            };
            var cls = ClassDefs.Get(classId);
            c.talents.Add(TalentTree.Instance.StartNodeFor(classId));
            c.equipped.Add(LootGenerator.StarterWeapon(cls));
            return c;
        }
    }
}
