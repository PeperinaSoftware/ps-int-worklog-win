#!/usr/bin/env bash
# install.sh - install / update / uninstall the Categorized ToDo plasmoid
# for the current user on Kubuntu 24.04 (KDE Plasma 5.27 + Qt 5.15).
#
# Usage:
#   ./install.sh             # install (or upgrade if already installed)
#   ./install.sh --uninstall # remove the plasmoid
#   ./install.sh --dev       # symlink the package (for live development)
#
# Requires `plasmapkg2` which is provided by plasma-framework (already on KDE).

set -euo pipefail

PLUGIN_ID="org.kde.plasma.categorizedtodo"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/package" && pwd)"

MODE="install"
for arg in "$@"; do
    case "$arg" in
        --uninstall) MODE="uninstall" ;;
        --dev)       MODE="dev" ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Prefer `kpackagetool5`; fall back to `plasmapkg2` if only that is installed.
if have_cmd kpackagetool5; then
    TOOL=(kpackagetool5 -t Plasma/Applet)
elif have_cmd plasmapkg2; then
    TOOL=(plasmapkg2 -t Plasma/Applet)
else
    echo "Neither kpackagetool5 nor plasmapkg2 is available." >&2
    echo "Install 'plasma-framework' or make sure you're on KDE Plasma." >&2
    exit 1
fi

echo "Using: ${TOOL[*]}"
echo "Package directory: $PKG_DIR"
echo "Plugin id: $PLUGIN_ID"

case "$MODE" in
    install)
        if "${TOOL[@]}" --list 2>/dev/null | grep -q "^$PLUGIN_ID$"; then
            echo "Upgrading existing installation…"
            "${TOOL[@]}" --upgrade "$PKG_DIR"
        else
            echo "Installing…"
            "${TOOL[@]}" --install "$PKG_DIR"
        fi
        ;;
    uninstall)
        echo "Uninstalling…"
        "${TOOL[@]}" --remove "$PLUGIN_ID"
        ;;
    dev)
        # Symlink into the user plasmoid directory so edits are live.
        TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$PLUGIN_ID"
        mkdir -p "$(dirname "$TARGET")"
        rm -rf "$TARGET"
        ln -s "$PKG_DIR" "$TARGET"
        echo "Symlinked: $TARGET -> $PKG_DIR"
        ;;
esac

echo
echo "Done. To apply changes in a running Plasma session:"
echo "  kquitapp5 plasmashell && kstart5 plasmashell"
echo
echo "Add the widget with: right-click desktop -> Add Widgets -> search \"ToDo\"."
