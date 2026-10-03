#!/bin/bash
# Sync AnkiKoFlash + TagBankHighlightSync into the dev emulator, then launch KOReader once.
#
# Usage:
#   bash dev-start.sh --emulator alice.epub
#   bash dev-start.sh --sync-only
#   bash dev-start.sh --appimage alice.epub
#   bash dev-start.sh -h | --help
#
# Environment: ANKIKOFLASH_SRC, TAGBANKHIGHLIGHTSYNC_SRC, KOREADER_DIR, KOREADER_MODE, KOREADER_APPIMAGE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dev-lib.sh
source "$SCRIPT_DIR/dev-lib.sh"

print_help() {
    cat <<'EOF'
dev-start.sh - Sync AnkiKoFlash + TagBankHighlightSync, launch KOReader once

Avoid two full emulator launches in one WSL session — a second launch often
triggers WSLg [WARN: COPY MODE] in the taskbar (not shown in terminal logs).

MODES
  emulator   Sync both plugins, then ./luajit reader.lua (DEFAULT off WSL)
  appimage   Launch Linux AppImage (still uses WSLg on WSL; no plugin sync)

USAGE
  bash dev-start.sh [--sync-only] [--appimage | --emulator] [book]
  bash dev-start.sh -h | --help

OPTIONS
  --sync-only       Rsync + symlink both plugins only; do not launch KOReader
  --setup-cloud     Run setup-emulator-cloud.sh, then sync and continue
  --emulator        Force emulator mode
  --appimage        Force AppImage mode
  book              Relative paths resolve against AnkiKoFlash repo

ENVIRONMENT
  ANKIKOFLASH_SRC                 AnkiKoFlash plugin source (default: this repo)
  TAGBANKHIGHLIGHTSYNC_SRC      TagBankHighlightSync plugin source
  KOREADER_DIR                  Emulator root (default: ~/koreader-dev/emulator/usr/lib/koreader)
  KOREADER_MODE                 appimage | emulator

EXAMPLES
  bash dev-start.sh --sync-only
  bash dev-start.sh --emulator alice.epub
  bash dev-start.sh --emulator /path/to/alice.epub
  bash dev-start.sh --setup-cloud --emulator alice.epub
EOF
}

MODE=""
SYNC_ONLY=0
SETUP_CLOUD=0
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
        --setup-cloud)
            SETUP_CLOUD=1
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

if [ "$SETUP_CLOUD" -eq 1 ]; then
    run_setup_emulator_cloud
fi

sync_both_plugins

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
