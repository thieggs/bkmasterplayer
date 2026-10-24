#!/usr/bin/env bash
# Gera o APK no notebook (thieggs-not), que compila bem mais rápido que o PC,
# e traz para dist/ daqui. Preparar o notebook antes, uma vez:
# ./dev/notebook_prepara.sh
#
# Uso: ./dev/build_apk_notebook.sh       (ALL_ABIS=1 passa para o build_apk.sh)
#      ./dev/build_apk_notebook.sh --so-copiar   (só manda o código e baixa as dependências)
#
# O notebook tem dual boot: no Windows ele é o `bkwin` e este script não acha.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOT="${NOT:-thieggs@192.168.1.67}"
SSH="ssh -i $HOME/.ssh/id_segunda_tela -o ConnectTimeout=5"
DEST="progeto-player-musica"

$SSH "$NOT" true 2>/dev/null || { echo "notebook não responde (desligado ou no Windows?)" >&2; exit 1; }

# Vai o que o git conhece (rastreado ou novo e não ignorado), mais a senha da
# chave. Nada de build/, .dart_tool/ nem local.properties: esses têm caminhos
# do PC, e lá o Flutter gera os dele.
cd "$ROOT"
{ git ls-files -co --exclude-standard; echo app/android/key.properties; } |
  rsync -a --ignore-missing-args --files-from=- -e "$SSH" "$ROOT/" "$NOT:$DEST/"

# libclang (do bindgen, que o signalsmith-stretch usa): o notebook não tem o
# LLVM; o notebook_prepara.sh copia o do PC para ~/.local/libclang, com os
# cabeçalhos do próprio clang (stddef.h…), que fora de /usr/lib/llvm-19 ele não acha.
ENV='export PATH=~/flutter/bin:~/.cargo/bin:$PATH ANDROID_HOME=~/android-sdk LIBCLANG_PATH=~/.local/libclang LD_LIBRARY_PATH=~/.local/libclang BINDGEN_EXTRA_CLANG_ARGS="-isystem $HOME/.local/libclang/include"'
if [ "${1:-}" = --so-copiar ]; then
  $SSH "$NOT" "$ENV; cd $DEST/app && nice -n 15 flutter pub get >/dev/null && echo 'código no notebook, dependências baixadas'"
  exit 0
fi

LOG="$ROOT/dist/build_notebook.log"
mkdir -p "$ROOT/dist"
$SSH "$NOT" "$ENV; cd $DEST && ALL_ABIS=${ALL_ABIS:-0} ./dev/build_apk.sh" 2>&1 | tee "$LOG"
APK=$(tail -1 "$LOG")
case "$APK" in */dist/bkmasterplayer_*.apk) ;; *) echo "build falhou (ver $LOG)" >&2; exit 1 ;; esac
rsync -a -e "$SSH" "$NOT:$APK" "$ROOT/dist/"
echo "$ROOT/dist/$(basename "$APK")"
