#!/bin/bash
# Сборка APK через Unity в batch-режиме. Требуется активированная лицензия Unity.
# Использование: tools/build_apk.sh [путь.apk]
set -e
UNITY=${UNITY:-$HOME/Unity/Hub/Editor/6000.3.26f1/Editor/Unity}
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
APK=${1:-$PROJ/Builds/rpg-game.apk}
"$UNITY" -batchmode -nographics -quit -projectPath "$PROJ" -buildTarget Android \
  -executeMethod RPG.EditorTools.BuildScript.BuildAndroid -apkPath "$APK" -logFile "$PROJ/Logs/build.log"
ls -la "$APK"
