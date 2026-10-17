using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace RPG.EditorTools
{
    /// <summary>
    /// Сборка APK: Unity -batchmode -quit -projectPath . -buildTarget Android -executeMethod RPG.EditorTools.BuildScript.BuildAndroid
    /// Путь к APK можно задать аргументом -apkPath путь.apk
    /// </summary>
    public static class BuildScript
    {
        [MenuItem("RPG/Собрать APK")]
        public static void BuildAndroid()
        {
            ProjectSetup.Run();
            string apk = "Builds/rpg-game.apk";
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++) if (args[i] == "-apkPath") apk = args[i + 1];
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(apk)));

            EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
            EditorUserBuildSettings.buildAppBundle = false;
            var opts = new BuildPlayerOptions
            {
                scenes = ProjectSetup.Scenes,
                locationPathName = apk,
                target = BuildTarget.Android,
                options = BuildOptions.None
            };
            var report = BuildPipeline.BuildPlayer(opts);
            var s = report.summary;
            Debug.Log($"[RPG] Build {s.result}: {s.outputPath} size={s.totalSize / 1024 / 1024} MB errors={s.totalErrors}");
            if (Application.isBatchMode) EditorApplication.Exit(s.result == BuildResult.Succeeded ? 0 : 1);
        }
    }
}
