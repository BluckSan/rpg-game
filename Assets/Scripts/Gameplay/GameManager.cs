using System.Collections;
using UnityEngine;

namespace RPG
{
    /// <summary>Управляет игровой сессией в зоне: игрок, камера, HUD, автосохранение, смерть/возрождение.</summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager Instance;
        public const int InventorySize = 30;
        public CharacterData Data;
        public PlayerCharacter Player;
        public Vector3 SpawnPoint = new Vector3(0, 0, -3);
        float autosave = 30f;

        public void Init(CharacterData c)
        {
            Instance = this;
            Data = c;
            var sp = GameObject.Find("SpawnPoint");
            if (sp != null) SpawnPoint = sp.transform.position;

            var go = new GameObject("Player");
            go.transform.position = c.hasPosition ? new Vector3(c.px, c.py + 0.2f, c.pz) : SpawnPoint;
            var cc = go.AddComponent<CharacterController>();
            cc.height = 1.9f; cc.radius = 0.4f; cc.center = new Vector3(0, 0.95f, 0); cc.stepOffset = 0.4f; cc.slopeLimit = 50;
            Player = go.AddComponent<PlayerCharacter>();
            Player.Init(c);
            go.AddComponent<PlayerController>();
            go.AddComponent<PlayerCombat>();

            var camGo = new GameObject("MainCamera"); camGo.tag = "MainCamera";
            var cam = camGo.AddComponent<Camera>();
            cam.fieldOfView = 55; cam.nearClipPlane = 0.3f; cam.farClipPlane = 160;
            cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = RenderSettings.fogColor;
            camGo.AddComponent<AudioListener>();
            var tpc = camGo.AddComponent<ThirdPersonCamera>(); tpc.target = go.transform;
            camGo.transform.position = go.transform.position + new Vector3(0, 8, -9);

            new GameObject("HUD").AddComponent<HUD>().Init(this);
            var zone = ZoneRegistry.Get(c.zoneId);
            Toast.Show(zone != null ? zone.displayName : "", 3f);
        }

        void Update()
        {
            autosave -= Time.unscaledDeltaTime;
            if (autosave <= 0) { autosave = 30f; Save(); }
        }

        public void Save()
        {
            if (Data == null || Player == null) return;
            if (!Player.Dead)
            {
                var p = Player.transform.position;
                Data.px = p.x; Data.py = p.y; Data.pz = p.z; Data.hasPosition = true;
            }
            SaveSystem.Save(Data);
        }

        void OnApplicationPause(bool paused) { if (paused) Save(); }
        void OnApplicationQuit() { Save(); }

        public void OnPlayerDied()
        {
            Toast.Show("Вы погибли... Возрождение у костра", 3f);
            // штраф: 10% опыта текущего уровня
            Data.xp = (long)(Data.xp * 0.9f);
            StartCoroutine(Respawn());
        }

        IEnumerator Respawn()
        {
            Player.Visual.enabled = false;
            Player.transform.GetChild(0).localRotation = Quaternion.Euler(-90, 0, 0);
            yield return new WaitForSeconds(3f);
            Player.transform.GetChild(0).localRotation = Quaternion.identity;
            Player.Visual.enabled = true;
            Player.GetComponent<PlayerController>().Teleport(SpawnPoint);
            Player.Recalc(true);
            Save();
        }

        public void ApplyCharacterChanges(bool rebuildVisual)
        {
            Player.Recalc();
            if (rebuildVisual) Player.RebuildVisual();
            Save();
        }
    }
}
