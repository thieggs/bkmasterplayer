#!/usr/bin/env bash
# Abre o Desktop Head Unit (DHU) — o emulador oficial de Android Auto — ligado
# no celular pelo adb, para ver o app na tela do carro sem carro nenhum.
#
# Uso: ./dev/android_auto.sh [720p|1080p|6in|wide|rotary|touchpad]
#
# Antes, UMA VEZ, no celular (não dá para fazer daqui, é tela do app):
#   1) Abra o Android Auto (Ajustes → Aplicativos → Android Auto → Configurações)
#   2) Toque 10x em "Versão" até liberar o modo desenvolvedor, e aceite
#   3) No menu ⋮ marque "Iniciar servidor da unidade principal"
# O celular precisa estar destravado e com o Android Auto já configurado.
set -euo pipefail
DHU="${ANDROID_HOME:-$HOME/android-sdk}/extras/google/auto"
[ -x "$DHU/desktop-head-unit" ] || {
  echo "DHU não instalado. Instale com:" >&2
  echo "  \"${ANDROID_HOME:-$HOME/android-sdk}/cmdline-tools/latest/bin/sdkmanager\" 'extras;google;auto'" >&2
  exit 1
}

# A tela do "carro": 720p é o padrão de fábrica; 6in imita uma central pequena.
case "${1:-720p}" in
  1080p) CFG=default_1080p.ini ;;
  6in) CFG=default_6in.ini ;;
  wide) CFG=default_wide.ini ;;
  rotary) CFG=rotary.ini ;;
  touchpad) CFG=touchpad.ini ;;
  *) CFG=default_720p.ini ;;
esac

DEV=$("$(dirname "$0")/adb_celular.sh" | tail -1)
echo "celular: $DEV"
# O DHU fala com o celular por esta porta; sem o encaminhamento ele não acha.
adb -s "$DEV" forward tcp:5277 tcp:5277 >/dev/null
echo "porta 5277 encaminhada · tela: $CFG"
echo
echo "Se travar em 'Waiting for device...', o servidor da unidade principal não"
echo "está ligado no celular: Android Auto → ⋮ → Iniciar servidor da unidade"
echo "principal (precisa do modo desenvolvedor, 10 toques em Versão)."
echo
cd "$DHU"
exec ./desktop-head-unit -a -c "config/$CFG"
