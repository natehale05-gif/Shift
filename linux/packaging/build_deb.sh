#!/usr/bin/env bash
# Packages the built Linux bundle as a .deb.
#
#   ./linux/packaging/build_deb.sh 0.2.0
#
# Produces dist/SHIFT-AI-linux-amd64.deb, which installs into /opt/shift with a
# launcher entry and icon, so the app appears in the desktop's application list
# rather than being a folder you unpack and run.
#
# The filename deliberately omits the version, against Debian convention: the
# README's install button points at
# releases/latest/download/SHIFT-AI-linux-amd64.deb, and that URL resolves only
# for an exact asset name. dpkg reads the version from the control file, not the
# filename, so nothing is lost.
#
# Note the consequence: /opt is root-owned, so a .deb install cannot replace
# itself. The app probes for that before downloading anything (see
# `canReplaceInPlace` in lib/core/update/update_installer_io.dart) and points at
# the release page instead of failing an update halfway through. The .tar.gz
# stays published for people who want the self-updating copy.
set -euo pipefail

VERSION="${1:?usage: build_deb.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
PKG="$ROOT/build/deb/shift-ai_${VERSION}_amd64"
OUT="$ROOT/dist"

test -x "$BUNDLE/shift" || { echo "no bundle at $BUNDLE — run flutter build linux --release first"; exit 1; }

rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" \
         "$PKG/opt/shift" \
         "$PKG/usr/bin" \
         "$PKG/usr/share/applications" \
         "$PKG/usr/share/icons/hicolor/512x512/apps" \
         "$OUT"

cp -r "$BUNDLE/." "$PKG/opt/shift/"
chmod 755 "$PKG/opt/shift/shift"

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

ln -sf /opt/shift/shift "$PKG/usr/bin/shift-ai"

# `StartupWMClass` has to match what the window actually reports, which is the
# GTK application id from linux/CMakeLists.txt — otherwise the running window
# gets its own dock entry beside the launcher's instead of being adopted by it.
cat > "$PKG/usr/share/applications/shift-ai.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=SHIFT AI
GenericName=AI workspace
Comment=Chat, code, images, design, work and notes in one app
Exec=/opt/shift/shift
Icon=shift-ai
Terminal=false
Categories=Utility;Office;
StartupWMClass=club.shiftai.shift
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
Description: SHIFT AI — chat, code, images, design, work and notes
 Six modes over one engine: talk to it, and it produces what you asked for —
 prose, a page, a picture, a designed document, a set of files, or clean text
 from your voice. A mode chooses the surface, not what is possible.
 .
 Sign in and a subscription covers the providers, or add your own key in
 Settings and the app talks to Anthropic, Google Gemini, OpenAI, Groq, Mistral
 or OpenRouter directly. Your own keys are stored on this device only.
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
