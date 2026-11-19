#!/usr/bin/env bash
# Builds the Linux app from windows/ (the Avalonia app runs on Linux too) and installs it for the current user:
#   ~/.local/share/scattered-notes/ScatteredNotes        self-contained, no .NET needed to run it
#   ~/.local/share/applications/scattered-notes.desktop  shows it in the app grid
#   ~/.local/share/icons/hicolor/256x256/apps/scattered-notes.png
# In the repo it builds first, which needs the .NET 10 SDK (see DEVELOPMENT.md). In an unpacked release download
# (ScatteredNotes-<version>-linux-<cpu>.tar.gz) it installs the ScatteredNotes file next to it; nothing else is
# needed. Run it again to update; notes and settings are kept.
#
# Usage: install.sh               build (in the repo) and install
#        install.sh --uninstall   remove the app, its launcher and its GNOME shortcuts
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA/scattered-notes"
DESKTOP_FILE="$DATA/applications/scattered-notes.desktop"
ICON="$DATA/icons/hicolor/256x256/apps/scattered-notes.png"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/scattered-notes.desktop"

case "$(uname -m)" in
    x86_64) RID=linux-x64 ;;
    aarch64 | arm64) RID=linux-arm64 ;;
    *) echo "Unsupported CPU: $(uname -m)" >&2; exit 1 ;;
esac

if [[ "${1:-}" == "--uninstall" ]]; then
    pkill -f "^$APP_DIR/ScatteredNotes( |$)" || true
    rm -rf "$APP_DIR"
    rm -f "$DESKTOP_FILE" "$ICON" "$AUTOSTART"
    if command -v gsettings >/dev/null; then
        LIST=org.gnome.settings-daemon.plugins.media-keys
        PREFIX=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
        current=$(gsettings get $LIST custom-keybindings)
        kept=$(echo "$current" | sed -E "s#'$PREFIX/scattered-notes-(capture|search)/'(, )?##g; s#, \]#]#; s#^@as ##")
        [[ "$kept" == "[]" ]] && kept="@as []"
        gsettings set $LIST custom-keybindings "$kept"
        for name in capture search; do
            gsettings reset-recursively "$LIST.custom-keybinding:$PREFIX/scattered-notes-$name/"
        done
    fi
    update-desktop-database "$DATA/applications" 2>/dev/null || true
    echo "Uninstalled. Your notes are still in the notes folder (~/Documents/ScatteredNotes by default)."
    exit 0
fi

if [[ -x "$HERE/ScatteredNotes" ]]; then
    # A release download: the app and its icon are next to this script
    BINARY="$HERE/ScatteredNotes"
    ICON_SOURCE="$HERE/scattered-notes.png"
else
    cd "$HERE/.."
    DOTNET="$(command -v dotnet || echo "$HOME/.dotnet/dotnet")"
    [[ -x "$DOTNET" ]] || { echo "The .NET 10 SDK is needed to build. See DEVELOPMENT.md." >&2; exit 1; }
    OUT="windows/artifacts/$RID"
    "$DOTNET" publish windows/src/ScatteredNotes.App -c Release -r "$RID" -o "$OUT"
    BINARY="$PWD/$OUT/ScatteredNotes"
    ICON_SOURCE="$PWD/windows/src/ScatteredNotes.App/Assets/AppIcon.png"
fi

# Quit a running copy so its file can be replaced
pkill -f "^$APP_DIR/ScatteredNotes( |$)" && sleep 1 || true
mkdir -p "$APP_DIR" "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON")"
install -m 755 "$BINARY" "$APP_DIR/ScatteredNotes.new"
mv -f "$APP_DIR/ScatteredNotes.new" "$APP_DIR/ScatteredNotes"
install -m 644 "$ICON_SOURCE" "$ICON"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Scattered Notes
Comment=Capture notes from anywhere; the Dashboard gathers your to-dos and dates
Exec="$APP_DIR/ScatteredNotes"
Icon=scattered-notes
Terminal=false
Categories=Office;
StartupWMClass=ScatteredNotes
Actions=QuickCapture;Search;

[Desktop Action QuickCapture]
Name=Quick Capture
Exec="$APP_DIR/ScatteredNotes" --quick-capture

[Desktop Action Search]
Name=Search All Notes
Exec="$APP_DIR/ScatteredNotes" --search
EOF
update-desktop-database "$DATA/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$DATA/icons/hicolor" 2>/dev/null || true
# A running GNOME Shell only rescans an icon theme when the theme folder itself changes, and a new file in
# 256x256/apps doesn't change it. Without this the app grid, dock and Alt+Tab show no icon until the next login.
touch "$DATA/icons/hicolor"

echo "Installed to $APP_DIR. Open Scattered Notes from the app grid, or run: $APP_DIR/ScatteredNotes"
if [[ -d /opt/scattered-notes ]]; then
    echo "Note: the .deb is installed too (/opt/scattered-notes). This copy takes its place in the app grid;"
    echo "use one or the other (sudo apt remove scattered-notes, or install.sh --uninstall)."
fi
