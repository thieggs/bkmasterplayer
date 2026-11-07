#!/usr/bin/env bash
# Gera o .ipa do BKmasterplayer para iPhone, sem assinatura. Roda num Mac com Xcode.
# Uso: ./dev/build_ios.sh              (saída: dist/BKmasterplayer-<versão>.ipa)
#
# Sem a conta paga de desenvolvedor da Apple, um iPhone só aceita app assinado
# com o Apple ID de quem instala: o iloader (Linux/Windows/Mac) ou o SideStore
# assinam na hora de instalar. Com Apple ID gratuito a assinatura vale 7 dias.
# Passo a passo e erros comuns em docs/IPHONE.md. Antes de distribuir, rode
# ./dev/confere_ipa.py no .ipa (o release.yml já roda).
#
# Limitação conhecida: a lista automática do Connect (broadcast UDP) no iOS
# exige a permissão de multicast da Apple, que conta gratuita não tem; pelo
# endereço funciona. A Festa acha os outros por Bonjour, que é liberado.
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
