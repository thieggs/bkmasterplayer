#!/usr/bin/env bash
# Gera o .ipa do BKmasterplayer para iPhone, sem assinatura. Roda num Mac com Xcode.
# Uso: ./dev/build_ios.sh              (saída: dist/BKmasterplayer-<versão>.ipa)
#
# Sem a conta paga de desenvolvedor da Apple, um iPhone só aceita app assinado
# com o Apple ID de quem instala: use o Sideloadly (Windows/Mac) ou o AltStore.
# Com Apple ID gratuito a assinatura vale 7 dias; depois é só reinstalar.
#
# Limitação conhecida: descobrir aparelhos na rede (Connect/Festa por UDP) no
# iOS exige a permissão de multicast da Apple, que conta gratuita não tem.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER=$(grep -m1 '^version:' "$ROOT/app/pubspec.yaml" | sed 's/version: *//; s/+.*//')
cd "$ROOT/app"
flutter build ios --release --no-codesign
APP="build/ios/iphoneos/Runner.app"
[ -d "$APP" ] || { echo "não achei $APP" >&2; exit 1; }
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/BKmasterplayer-$VER.ipa"
rm -f "$OUT"
(cd "$STAGE" && zip -qry "$OUT" Payload)
echo "$OUT"
