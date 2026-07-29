#!/usr/bin/env bash
# Packages the built Linux bundle as a .deb.
#
#   ./linux/packaging/build_deb.sh 0.1.2
#
# Produces dist/SHIFT-AI-linux-amd64.deb, which installs into /opt/shift-ai
# with a launcher entry and icon, so the app appears in the desktop's
# application list rather than being a folder you unpack and run.
#
# The filename deliberately omits the version, against Debian convention: the
# README's install button points at
# releases/latest/download/SHIFT-AI-linux-amd64.deb, and that URL resolves only
# for an exact asset name. dpkg reads the version from the control file, not
# the filename, so nothing is lost.
#
# Note the consequence: /opt is root-owned, so a .deb install cannot replace
# itself. The app probes for that (see canReplaceInPlace in
# lib/core/update/update_installer_io.dart) and points at the release page
# instead of failing an update halfway through. The .tar.gz stays published
# for people who want the self-updating copy.
set -euo pipefail

VERSION="${1:?usage: build_deb.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
PKG="$ROOT/build/deb/shift-ai_${VERSION}_amd64"
OUT="$ROOT/dist"

test -x "$BUNDLE/shift_ai" || { echo "no bundle at $BUNDLE — run flutter build linux --release first"; exit 1; }

rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" \
         "$PKG/opt/shift-ai" \
         "$PKG/usr/bin" \
         "$PKG/usr/share/applications" \
         "$PKG/usr/share/icons/hicolor/512x512/apps" \
         "$OUT"

cp -r "$BUNDLE/." "$PKG/opt/shift-ai/"
chmod 755 "$PKG/opt/shift-ai/shift_ai"

# The app icon, at the size the hicolor theme expects.
if [ -f "$ROOT/assets/icon/app_icon.png" ]; then
  if command -v convert >/dev/null 2>&1; then
    convert "$ROOT/assets/icon/app_icon.png" -resize 512x512 \
      "$PKG/usr/share/icons/hicolor/512x512/apps/shift-ai.png"
  else
    cp "$ROOT/assets/icon/app_icon.png" \
      "$PKG/usr/share/icons/hicolor/512x512/apps/shift-ai.png"
  fi
fi

ln -sf /opt/shift-ai/shift_ai "$PKG/usr/bin/shift-ai"

cat > "$PKG/usr/share/applications/shift-ai.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=SHIFT AI
GenericName=AI Studio
Comment=Routes your request to the right specialised AI studio
Exec=/opt/shift-ai/shift_ai
Icon=shift-ai
Terminal=false
Categories=Utility;Office;
StartupWMClass=club.shiftai.shift_ai
DESKTOP

INSTALLED_KB="$(du -ks "$PKG/opt" | cut -f1)"

cat > "$PKG/DEBIAN/control" <<CONTROL
Package: shift-ai
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: shiftai.club <noreply@shiftai.club>
Installed-Size: ${INSTALLED_KB}
Depends: libgtk-3-0, libglib2.0-0, libstdc++6, zlib1g
Homepage: https://github.com/natehale05-gif/Shift
Description: SHIFT AI — one studio, every AI tool
 Talk to SHIFT AI like you would a person and it routes the request to the
 right specialised studio: image, video, voice, avatar, translation, decks,
 short reels, music, brand packs or code.
 .
 Runs in demo mode with no account. Add your own provider key in Settings and
 the same requests run against Anthropic, Google Gemini, OpenAI, Groq,
 Mistral, OpenRouter, Flux or Heygen. Keys are stored on this device only.
CONTROL

# Refresh the desktop database and icon cache so the launcher entry appears
# without a re-login. Both tools are optional on minimal systems.
cat > "$PKG/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
exit 0
POSTINST
chmod 755 "$PKG/DEBIAN/postinst"

cat > "$PKG/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
exit 0
POSTRM
chmod 755 "$PKG/DEBIAN/postrm"

dpkg-deb --build --root-owner-group "$PKG" "$OUT/SHIFT-AI-linux-amd64.deb"
echo "built $OUT/SHIFT-AI-linux-amd64.deb"
