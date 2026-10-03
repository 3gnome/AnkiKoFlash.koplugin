#!/bin/bash
# Launch KOReader with the AnkiKoFlash plugin only (see dev-start.sh for both plugins).
#
# Usage:
#   bash start.sh --sync-only
#   bash start.sh --emulator alice.epub
#   bash start.sh --appimage alice.epub
#   bash start.sh -h | --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dev-lib.sh
source "$SCRIPT_DIR/dev-lib.sh"

ANKIKOFLASH_SRC="${PLUGIN_DIR:-$SCRIPT_DIR}"

print_help() {
    cat <<'EOF'
start.sh - Launch KOReader with the AnkiKoFlash plugin

For AnkiKoFlash + TagBankHighlightSync together, use: bash dev-start.sh --emulator [book]

MODES
  appimage   Launch AppImage (DEFAULT on WSL; still uses WSLg; no plugin sync)
  emulator   Sync this plugin, then ./luajit reader.lua (DEFAULT off WSL)

USAGE
  bash start.sh [--sync-only] [--appimage | --emulator] [book]
  bash start.sh -h | --help

OPTIONS
  --sync-only       Rsync + symlink this plugin only; do not launch
  --emulator        Force emulator mode
  --appimage        Force AppImage mode
  book              Relative paths resolve against this repo

ENVIRONMENT
  KOREADER_MODE, KOREADER_APPIMAGE, KOREADER_DIR, PLUGIN_DIR, PLUGIN_DST

EXAMPLES
  bash start.sh --sync-only
  bash start.sh --emulator alice.epub
  bash dev-start.sh --emulator alice.epub   # both plugins, one launch
EOF
}

MODE=""
SYNC_ONLY=0
BOOK_ARG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        --sync-only)
            SYNC_ONLY=1
            shift
            ;;
        --appimage)
            MODE="appimage"
            shift
            ;;
        --emulator)
            MODE="emulator"
            shift
            ;;
        --)
            shift
            if [ "$#" -gt 0 ]; then
                BOOK_ARG="$1"
                shift
            fi
            ;;
        *)
            BOOK_ARG="$1"
            shift
            ;;
    esac
done

if [ -z "$MODE" ] && [ -n "${KOREADER_MODE:-}" ]; then
    MODE="$KOREADER_MODE"
fi
if [ -z "$MODE" ]; then
    MODE="$(default_mode)"
fi

BOOK="$(resolve_book "$SCRIPT_DIR" "$BOOK_ARG")"
if [ -n "$BOOK" ] && [ ! -e "$BOOK" ]; then
    echo "WARNING: Book not found: $BOOK -- launching without a book." >&2
    BOOK=""
fi

if [ "$MODE" = "emulator" ] || [ "$SYNC_ONLY" -eq 1 ]; then
    if [ ! -d "$KOREADER" ]; then
        echo "ERROR: KOReader emulator not found at: $KOREADER" >&2
        exit 1
    fi
    sync_ankikoflash "$ANKIKOFLASH_SRC" "${PLUGIN_DST:-$ANKIKOFLASH_DST}"
fi

if [ "$SYNC_ONLY" -eq 1 ]; then
    echo "Sync complete (--sync-only; no launch)." >&2
    exit 0
fi

case "$MODE" in
    appimage)
        launch_appimage "$BOOK"
        ;;
    emulator)
        launch_emulator "$BOOK"
        ;;
    *)
        echo "ERROR: Unknown mode: $MODE (expected 'appimage' or 'emulator')." >&2
        exit 1
        ;;
esac
