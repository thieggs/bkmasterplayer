#!/usr/bin/env bash
# Gera o APK do BKT Player para celulares Android (arm64, quase todos os atuais).
# Uso: ./dev/build_apk.sh            (ou ALL_ABIS=1 para incluir arm 32 bits e x86_64)
# Saída: dist/bktplayer_<versão>_<abi>.apk
#
# Requisitos: Android SDK com NDK 28.2 (ANDROID_HOME, padrão ~/android-sdk).
# A assinatura vem de app/android/key.properties (fora do git); sem ele, o APK
# sai com a chave de debug e não atualiza por cima de um instalado com a outra.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
BASE=$(grep -m1 '^version:' "$ROOT/app/pubspec.yaml" | sed 's/version: *//; s/+.*//')
# versionCode crescente a cada build (o Android só atualiza para um código maior).
CODE=$(( $(date +%s) / 60 - 29000000 ))
if [ "${ALL_ABIS:-0}" = 1 ]; then PLATFORMS=android-arm,android-arm64,android-x64; ABI=universal; else PLATFORMS=android-arm64; ABI=arm64; fi
cd "$ROOT/app"
# O cargokit não apaga o motor de ABIs de builds anteriores (ex.: x86_64 do emulador).
rm -rf build/player_engine/jniLibs
flutter build apk --release --target-platform "$PLATFORMS" --build-name "$BASE" --build-number "$CODE"
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/bktplayer_${BASE}+${CODE}_${ABI}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"
echo "$OUT"
