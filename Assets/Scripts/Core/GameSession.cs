using UnityEngine;
using UnityEngine.SceneManagement;

namespace RPG
{
    /// <summary>Глобальное состояние: текущий персонаж и переходы между сценами.</summary>
    public static class GameSession
    {
        public static CharacterData Current;
        public const string MainMenuScene = "MainMenu";

        public static void Play(CharacterData c)
        {
            Current = c;
            var zone = ZoneRegistry.Get(c.zoneId) ?? ZoneRegistry.Get(ZoneRegistry.StarterZone);
            if (!zone.available) zone = ZoneRegistry.Get(ZoneRegistry.StarterZone);
            c.zoneId = zone.id;
            SceneManager.LoadScene(zone.sceneName);
        }

        public static void TravelTo(string zoneId)
        {
            var zone = ZoneRegistry.Get(zoneId);
            if (zone == null || !zone.available) return;
            if (Current != null) { Current.zoneId = zoneId; Current.hasPosition = false; SaveSystem.Save(Current); }
            SceneManager.LoadScene(zone.sceneName);
        }

        public static void ToMenu()
        {
            if (Current != null) SaveSystem.Save(Current);
            SceneManager.LoadScene(MainMenuScene);
        }
    }
}
