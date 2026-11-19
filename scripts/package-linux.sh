#!/usr/bin/env bash
# Builds the Linux downloads for a release into build/release-linux/, for x64 and arm64:
#   ScatteredNotes-<version>-linux-<cpu>.tar.gz   the app, its icon and install.sh (per-user install, no root)
#   scattered-notes_<version>_<arch>.deb          for Ubuntu and Debian: installs to /opt for every user
#   SHA256SUMS
# Needs the .NET 10 SDK and dpkg-deb. The version comes from windows/Directory.Build.props.
#
# Usage: scripts/package-linux.sh
set -euo pipefail
# Package files must not be group-writable, whatever this machine's default is
umask 022
cd "$(dirname "$0")/.."

DOTNET="$(command -v dotnet || echo "$HOME/.dotnet/dotnet")"
[[ -x "$DOTNET" ]] || { echo "The .NET 10 SDK is needed. See DEVELOPMENT.md." >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "dpkg-deb is needed (sudo apt install dpkg-dev)." >&2; exit 1; }

VERSION=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' windows/Directory.Build.props)
OUT=build/release-linux
ICON_SOURCE=windows/src/ScatteredNotes.App/Assets/AppIcon.png
rm -rf "$OUT"
mkdir -p "$OUT"

for RID in linux-x64 linux-arm64; do
    case "$RID" in
        linux-x64) ARCH=amd64 ;;
        linux-arm64) ARCH=arm64 ;;
    esac
    PUBLISH="windows/artifacts/$RID"
    "$DOTNET" publish windows/src/ScatteredNotes.App -c Release -r "$RID" -o "$PUBLISH"

    # The tar.gz: unpack and run install.sh
    NAME="ScatteredNotes-$VERSION-$RID"
    mkdir -p "$OUT/$NAME"
    install -m 755 "$PUBLISH/ScatteredNotes" "$OUT/$NAME/ScatteredNotes"
    install -m 644 "$ICON_SOURCE" "$OUT/$NAME/scattered-notes.png"
    install -m 755 scripts/install-linux.sh "$OUT/$NAME/install.sh"
    tar -C "$OUT" -czf "$OUT/$NAME.tar.gz" "$NAME"
    rm -rf "${OUT:?}/$NAME"

    # The .deb
    ROOT="$OUT/deb-$ARCH"
    install -D -m 755 "$PUBLISH/ScatteredNotes" "$ROOT/opt/scattered-notes/ScatteredNotes"
    install -D -m 644 "$ICON_SOURCE" "$ROOT/usr/share/icons/hicolor/256x256/apps/scattered-notes.png"
    mkdir -p "$ROOT/usr/bin" "$ROOT/usr/share/applications" "$ROOT/usr/share/doc/scattered-notes" "$ROOT/DEBIAN"
    # So "scattered-notes --quick-capture" works from a terminal or another desktop's shortcut settings
    ln -s /opt/scattered-notes/ScatteredNotes "$ROOT/usr/bin/scattered-notes"
    cat > "$ROOT/usr/share/applications/scattered-notes.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Scattered Notes
Comment=Capture notes from anywhere; the Dashboard gathers your to-dos and dates
Exec=/opt/scattered-notes/ScatteredNotes
Icon=scattered-notes
Terminal=false
Categories=Office;
StartupWMClass=ScatteredNotes
Actions=QuickCapture;Search;

[Desktop Action QuickCapture]
Name=Quick Capture
Exec=/opt/scattered-notes/ScatteredNotes --quick-capture

[Desktop Action Search]
Name=Search All Notes
Exec=/opt/scattered-notes/ScatteredNotes --search
EOF
    cat > "$ROOT/usr/share/doc/scattered-notes/copyright" <<EOF
Scattered Notes
Source: https://github.com/and/scattered-notes
EOF
    SIZE=$(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)
    cat > "$ROOT/DEBIAN/control" <<EOF
Package: scattered-notes
Version: $VERSION
Section: editors
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE
Depends: libc6, libstdc++6, libgcc-s1, libicu78 | libicu76 | libicu74 | libicu72 | libicu70, libfontconfig1, libfreetype6, libx11-6, libice6, libsm6, libdbus-1-3
Maintainer: Scattered Notes <scatterednotes@local>
Homepage: https://github.com/and/scattered-notes
Description: Capture notes from anywhere; the Dashboard gathers your to-dos
 Jot a thought in seconds with a global shortcut (Ctrl+Alt+N), and the
 Dashboard collects every to-do and every line that mentions a day from all
 your notes. Notes are plain Markdown files, and an Obsidian vault works as
 it is.
EOF
    # Debian's own triggers refresh the app list and icon cache when /usr/share changes
    dpkg-deb --root-owner-group --build "$ROOT" "$OUT/scattered-notes_${VERSION}_$ARCH.deb" >/dev/null
    rm -rf "$ROOT"
done

(cd "$OUT" && sha256sum ./*.tar.gz ./*.deb | sed 's# \./# #' > SHA256SUMS)
echo "Built in $OUT:"
ls -1 "$OUT"
