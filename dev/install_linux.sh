#!/usr/bin/env bash
# Instala o app para o usuário atual (sem sudo): copia o build release para
# ~/.local/share/player-musica e cria o atalho no menu de aplicativos.
# Uso: ./dev/install_linux.sh        (depois de `flutter build linux --release`)
#      ./dev/install_linux.sh --remove
set -euo pipefail
APP_ID="io.github.playermusica.player_musica"
DEST="$HOME/.local/share/player-musica"
DESKTOP="$HOME/.local/share/applications/$APP_ID.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"

if [ "${1:-}" = "--remove" ]; then
  rm -rf "$DEST" "$DESKTOP" "$ICON_DIR/$APP_ID.png"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  echo "Removido."
  exit 0
fi

BUNDLE="$(cd "$(dirname "$0")/../app/build/linux/x64/release/bundle" && pwd)"
[ -x "$BUNDLE/player_musica" ] || { echo "Compile antes: cd app && flutter build linux --release"; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST" "$(dirname "$DESKTOP")" "$ICON_DIR"
cp -r "$BUNDLE/." "$DEST/"
cp "$BUNDLE/data/flutter_assets/assets/icon/icon.png" "$ICON_DIR/$APP_ID.png"
cat > "$DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Player de Música
GenericName=Player de música
Comment=Player para Navidrome/OpenSubsonic com AutoMix DJ
Exec=$DEST/player_musica
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Audio;Player;Music;
Keywords=música;navidrome;subsonic;player;dj;
StartupWMClass=$APP_ID
DESK
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Instalado em $DEST — procure \"Player de Música\" no menu de aplicativos."
