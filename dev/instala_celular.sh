#!/usr/bin/env bash
# Instala o APK no celular pelo adb Wi-Fi.
#
# O `-i com.android.vending` não é enfeite: o Android Auto **esconde do carro**
# todo app cujo instalador não seja a Play Store. Instalado pelo adb cru o
# `installerPackageName` fica `null` e o app simplesmente não aparece no rádio —
# só dando um jeito nisso ou deixando ligado o modo desenvolvedor do Android
# Auto com "Fontes desconhecidas". Com a flag, aparece sem depender de nada.
#
# Uso: ./dev/instala_celular.sh [caminho-do-apk]   (padrão: o mais novo de dist/)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="${1:-$(ls -t "$ROOT"/dist/bkmasterplayer_*.apk 2>/dev/null | head -1)}"
[ -f "$APK" ] || { echo "sem APK em dist/ — rode ./dev/build_apk.sh" >&2; exit 1; }

DEV=$("$(dirname "$0")/adb_celular.sh" | tail -1)
echo "celular: $DEV"
echo "apk: $(basename "$APK")"
adb -s "$DEV" install -r -i com.android.vending "$APK"

quem=$(adb -s "$DEV" shell "dumpsys package io.github.playermusica.player_musica" 2>/dev/null |
  grep -m1 -i installerPackageName | tr -d ' \r')
echo "$quem"
case "$quem" in
  *com.android.vending) echo "ok: o Android Auto vai mostrar o app no carro" ;;
  *) echo "ATENÇÃO: instalador não ficou como Play Store; o carro pode esconder o app" >&2 ;;
esac
