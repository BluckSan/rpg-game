using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace RPG.EditorTools
{
    /// <summary>
    /// Генерирует сцены, материалы и настройки проекта. Меню: RPG → Настроить проект.
    /// Batch: Unity -batchmode -projectPath . -executeMethod RPG.EditorTools.ProjectSetup.Run -quit
    /// </summary>
    public static class ProjectSetup
    {
        public static readonly string[] Scenes = { "Assets/Scenes/MainMenu.unity", "Assets/Scenes/StarterZone.unity" };

        [MenuItem("RPG/Настроить проект")]
        public static void Run()
        {
            CreateMaterials();
            CreateScenes();
            ConfigurePlayer();
            AssetDatabase.SaveAssets();
            Debug.Log("[RPG] Проект настроен");
        }

        static void CreateMaterials()
        {
            Directory.CreateDirectory("Assets/Resources/Materials");
            MakeMat("Assets/Resources/Materials/Base.mat", "Standard", false);
            MakeMat("Assets/Resources/Materials/BaseEmissive.mat", "Standard", true);
            MakeMat("Assets/Resources/Materials/FX.mat", "Sprites/Default", false);
        }

        static void MakeMat(string path, string shader, bool emissive)
        {
            if (AssetDatabase.LoadAssetAtPath<Material>(path) != null) return;
            var m = new Material(Shader.Find(shader));
            if (emissive)
            {
                m.EnableKeyword("_EMISSION");
                m.SetColor("_EmissionColor", Color.white);
                m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
            }
            AssetDatabase.CreateAsset(m, path);
        }

        static void CreateScenes()
        {
            Directory.CreateDirectory("Assets/Scenes");
            var menu = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            new GameObject("Bootstrap").AddComponent<MainMenuBootstrap>();
            RenderSettings.fog = true; RenderSettings.fogMode = FogMode.Linear;
            EditorSceneManager.SaveScene(menu, Scenes[0]);

            var zone = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            new GameObject("Bootstrap").AddComponent<ZoneBootstrap>().zoneId = ZoneRegistry.StarterZone;
            RenderSettings.fog = true; RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            EditorSceneManager.SaveScene(zone, Scenes[1]);

            // Будущая глобальная карта: добавить "Assets/Scenes/GlobalMap.unity" сюда и в ZoneRegistry (available = true).
            EditorBuildSettings.scenes = System.Array.ConvertAll(Scenes, s => new EditorBuildSettingsScene(s, true));
            EditorSceneManager.OpenScene(Scenes[0]);
        }

        static void ConfigurePlayer()
        {
            var android = NamedBuildTarget.Android;
            PlayerSettings.companyName = "BluckSan";
            PlayerSettings.productName = "Осколки Эфира";
            PlayerSettings.bundleVersion = "0.1.0";
            PlayerSettings.Android.bundleVersionCode = 1;
            PlayerSettings.SetApplicationIdentifier(android, "com.blucksan.rpggame");
            PlayerSettings.SetScriptingBackend(android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.SetManagedStrippingLevel(android, ManagedStrippingLevel.Low);
            PlayerSettings.stripEngineCode = true;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.colorSpace = ColorSpace.Gamma;
            PlayerSettings.SplashScreen.showUnityLogo = false; // работает только с Pro; на Personal игнорируется
            PlayerSettings.Android.preferredInstallLocation = AndroidPreferredInstallLocation.Auto;

            // Старый Input Manager (используем Input.touches) — 0 = Input Manager, 2 = оба
            var ps = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
            if (ps != null && ps.Length > 0)
            {
                var so = new SerializedObject(ps[0]);
                var p = so.FindProperty("activeInputHandler");
                if (p != null) { p.intValue = 0; so.ApplyModifiedProperties(); }
            }

            // Не вырезать вариант линейного тумана у шейдеров
            var gs = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset");
            if (gs != null && gs.Length > 0)
            {
                var so = new SerializedObject(gs[0]);
                var fs = so.FindProperty("m_FogStripping"); if (fs != null) fs.intValue = 1;
                var fl = so.FindProperty("m_FogKeepLinear"); if (fl != null) fl.boolValue = true;
                so.ApplyModifiedProperties();
            }

            // Качество: одна средняя настройка для телефонов
            QualitySettings.shadowDistance = 45;
            QualitySettings.vSyncCount = 0;
        }
    }
}
