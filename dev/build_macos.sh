#!/usr/bin/env bash
# Gera o .dmg do BKmasterplayer para macOS. Roda num Mac com Xcode.
# Uso: ./dev/build_macos.sh            (saída: dist/BKmasterplayer-<versão>.dmg)
#
# Sem conta de desenvolvedor da Apple o app sai com assinatura local (ad hoc):
# roda, mas o Gatekeeper diz que "está danificado" em outro Mac. Quem baixar
# resolve uma vez com:  xattr -dr com.apple.quarantine /Applications/BKmasterplayer.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER=$(grep -m1 '^version:' "$ROOT/app/pubspec.yaml" | sed 's/version: *//; s/+.*//')
cd "$ROOT/app"
flutter build macos --release
APP="build/macos/Build/Products/Release/BKmasterplayer.app"
[ -d "$APP" ] || { echo "não achei $APP" >&2; exit 1; }
# Informativo: arquiteturas do executável e do motor (Intel e/ou Apple Silicon).
lipo -info "$APP/Contents/MacOS/BKmasterplayer" >&2 || true
# Pasta de montagem com o atalho de Aplicativos, o arrastar-e-soltar de sempre.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/BKmasterplayer-$VER.dmg"
rm -f "$OUT"
hdiutil create -volname "BKmasterplayer" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >&2
echo "$OUT"
