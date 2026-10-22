#!/usr/bin/env bash
# Prepara o notebook (thieggs-not) para compilar o APK: ele é bem mais rápido
# que o PC (i7-1355U, 12 threads, contra o Xeon E3-1230 V2). Roda uma vez,
# daqui do PC; depois é só ./dev/build_apk_notebook.sh.
#
# Sem sudo: tudo fica na pasta do usuário de lá.
# - Do PC, pela rede: Android SDK (só o que o build usa, ~3,3 GB), o JDK 21 (o
#   Java do sistema lá é o 25, que o Gradle não aceita) e a chave de assinatura.
# - Baixado lá: Flutter (mesma versão do PC) e Rust (com os alvos Android).
#
# Tudo com nice/ionice: o notebook costuma estar analisando músicas (BK Analyzer).
# Pode rodar de novo: o que já está lá é pulado ou só atualizado.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOT="${NOT:-thieggs@192.168.1.67}"
KEY="$HOME/.ssh/id_segunda_tela"
SSH="ssh -i $KEY -o ConnectTimeout=5"
LENTO="nice -n 15 ionice -c3"

FLUTTER_VER=$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p')
RUST_VER=$(rustc --version | cut -d' ' -f2)
JDK="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
echo "Flutter $FLUTTER_VER, Rust $RUST_VER, JDK $JDK"

$SSH "$NOT" true 2>/dev/null || { echo "notebook não responde (desligado ou no Windows?)" >&2; exit 1; }

echo "== Android SDK"
$SSH "$NOT" "mkdir -p ~/android-sdk ~/.local ~/.android"
# Sem o emulador e as imagens de sistema: não servem para compilar.
for d in build-tools cmake cmdline-tools licenses ndk platforms platform-tools; do
  $LENTO rsync -a --info=progress2 -e "$SSH" "$HOME/android-sdk/$d" "$NOT:android-sdk/"
done

echo "== JDK 21"
$LENTO rsync -a -e "$SSH" "$JDK/" "$NOT:.local/jdk21/"

echo "== chave de assinatura"
STORE=$(sed -n 's/^storeFile=//p' "$ROOT/app/android/key.properties")
rsync -a -e "$SSH" "$STORE" "$NOT:$STORE"

echo "== Flutter $FLUTTER_VER e Rust $RUST_VER (lá)"
$SSH "$NOT" "bash -s" <<EOF
set -euo pipefail
if [ ! -x ~/flutter/bin/flutter ]; then
  $LENTO git clone --depth 1 -b $FLUTTER_VER https://github.com/flutter/flutter.git ~/flutter
fi
export PATH=~/flutter/bin:~/.cargo/bin:\$PATH
flutter --disable-analytics >/dev/null 2>&1 || true
flutter config --no-analytics --android-sdk ~/android-sdk --jdk-dir ~/.local/jdk21 >/dev/null
$LENTO flutter precache --android
if ! command -v rustup >/dev/null; then
  curl -sSf https://sh.rustup.rs | $LENTO sh -s -- -y --profile minimal --default-toolchain $RUST_VER
fi
rustup toolchain install $RUST_VER --profile minimal
rustup default $RUST_VER
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
flutter --version | head -1
rustc --version
EOF

echo "== código do projeto"
"$ROOT/dev/build_apk_notebook.sh" --so-copiar

echo "pronto: ./dev/build_apk_notebook.sh"
