#!/usr/bin/env bash
# Gera o pacote .deb do BKmasterplayer a partir do build release (instala em /opt/bkmasterplayer).
# Uso: ./dev/build_deb.sh            (depois de `cd app && flutter build linux --release`)
# Saída: dist/bkmasterplayer_<versão>_amd64.deb
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
[ -x "$BUNDLE/player_musica" ] || { echo "Compile antes: cd app && flutter build linux --release"; exit 1; }
APP_ID="io.github.playermusica.player_musica"
BASE=$(grep -m1 '^version:' "$ROOT/app/pubspec.yaml" | sed 's/version: *//; s/+.*//')
VERSION="${BASE}+$(date +%Y%m%d%H%M)"
PKG="$ROOT/dist/pkg"
rm -rf "$PKG" && mkdir -p "$PKG/DEBIAN" "$PKG/opt/bkmasterplayer" "$PKG/usr/bin" \
  "$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/512x512/apps" "$PKG/usr/share/icons/hicolor/256x256/apps"
cp -r "$BUNDLE/." "$PKG/opt/bkmasterplayer/"
ln -s /opt/bkmasterplayer/player_musica "$PKG/usr/bin/bkmasterplayer"
cp "$BUNDLE/data/flutter_assets/assets/icon/icon.png" "$PKG/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
cp "$ROOT/app/assets/icon/icon_256.png" "$PKG/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
cat > "$PKG/usr/share/applications/$APP_ID.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=BKmasterplayer 🎵
GenericName=Player de música
Comment=Player para Navidrome/OpenSubsonic com AutoMix DJ
Exec=/opt/bkmasterplayer/player_musica
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Audio;Player;Music;
Keywords=música;navidrome;subsonic;player;dj;
StartupWMClass=$APP_ID
DESK
cat > "$PKG/DEBIAN/control" <<CTRL
Package: bkmasterplayer
Version: $VERSION
Section: sound
Priority: optional
Architecture: amd64
Maintainer: thieggs <thiago123azfr@gmail.com>
Depends: libgtk-3-0t64 | libgtk-3-0, libayatana-appindicator3-1, libsecret-1-0, libasound2t64 | libasound2, libepoxy0
Description: BKmasterplayer - player de música com AutoMix DJ
 Player para Navidrome/OpenSubsonic com transições de DJ sincronizadas por
 BPM (AutoMix), gapless, equalizador, rádio sônica (AudioMuse) e offline.
CTRL
cat > "$PKG/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q /usr/share/icons/hicolor || true
POST
chmod -R u=rwX,go=rX "$PKG"
chmod 755 "$PKG/DEBIAN/postinst"
OUT="$ROOT/dist/bkmasterplayer_${VERSION}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "$PKG" "$OUT" >/dev/null
rm -rf "$PKG"
echo "$OUT"
