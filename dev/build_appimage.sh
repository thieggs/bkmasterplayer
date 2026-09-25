#!/usr/bin/env bash
# Gera o .AppImage do BKmasterplayer: um arquivo só, que roda em qualquer
# distribuição sem instalar nada.
#
# Uso: ./dev/build_appimage.sh        (depois de `cd app && flutter build linux --release`)
# Saída: dist/BKmasterplayer-<versão>-x86_64.AppImage
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
[ -x "$BUNDLE/player_musica" ] || { echo "Compile antes: cd app && flutter build linux --release" >&2; exit 1; }

APP_ID="io.github.playermusica.player_musica"
VERSION=$(grep -m1 '^version:' "$ROOT/app/pubspec.yaml" | sed 's/version: *//; s/+.*//')
DIR="$ROOT/dist/AppDir"
rm -rf "$DIR"
mkdir -p "$DIR/usr/bin" "$DIR/usr/share/applications" "$DIR/usr/share/icons/hicolor/512x512/apps"

# O binário procura lib/ e data/ ao lado dele, então o pacote inteiro vai junto.
cp -r "$BUNDLE/." "$DIR/usr/bin/"

cat > "$DIR/$APP_ID.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=BKmasterplayer 🎵
GenericName=Player de música
Comment=Player para Navidrome/OpenSubsonic com AutoMix DJ
Exec=player_musica
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Audio;Player;Music;
Keywords=música;navidrome;subsonic;player;dj;
StartupWMClass=$APP_ID
DESK
cp "$DIR/$APP_ID.desktop" "$DIR/usr/share/applications/"
cp "$BUNDLE/data/flutter_assets/assets/icon/icon.png" "$DIR/$APP_ID.png"
cp "$DIR/$APP_ID.png" "$DIR/usr/share/icons/hicolor/512x512/apps/"

cat > "$DIR/AppRun" <<'RUN'
#!/bin/sh
AQUI="$(dirname "$(readlink -f "$0")")"
exec "$AQUI/usr/bin/player_musica" "$@"
RUN
chmod +x "$DIR/AppRun"

# O appimagetool é ele mesmo um AppImage; --appimage-extract-and-run evita
# precisar de FUSE, que não existe em runner de CI nem em container.
FERRAMENTA="$ROOT/dist/appimagetool"
if [ ! -x "$FERRAMENTA" ]; then
  echo "baixando o appimagetool..." >&2
  curl -fsSL -o "$FERRAMENTA" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$FERRAMENTA"
fi

OUT="$ROOT/dist/BKmasterplayer-$VERSION-x86_64.AppImage"
rm -f "$OUT"
ARCH=x86_64 "$FERRAMENTA" --appimage-extract-and-run "$DIR" "$OUT" >/dev/null 2>&1
rm -rf "$DIR"
echo "$OUT"
