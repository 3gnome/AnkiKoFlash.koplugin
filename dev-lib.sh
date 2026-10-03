# Shared KOReader dev helpers (source from start.sh / dev-start.sh; not executed directly).
# Sets: KOREADER, ANKIKOFLASH_*, TAGBANKHIGHLIGHTSYNC_* (HIGHLIGHTSYNC_* kept as legacy aliases)

: "${KOREADER:="${KOREADER_DIR:-$HOME/koreader-dev/emulator/usr/lib/koreader}"}"
# OCR harness capture dir (Windows-hosted, reached from WSL via /mnt/c). The
# dev-capture.lua watcher is a no-op unless this is set. Set it to your capture
# folder to turn the watcher on during dev, e.g.
#   export KOREADER_CAPTURE_DIR=/mnt/c/Users/<you>/Dev/koreader-dev/.qa-frames
# (Kept unset by default so no personal path is committed.)
: "${KOREADER_CAPTURE_DIR:=}"
export KOREADER_CAPTURE_DIR
_DEV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
: "${ANKIKOFLASH_SRC:="${_DEV_LIB_DIR:-.}"}"
: "${TAGBANKHIGHLIGHTSYNC_SRC:="$(dirname "${ANKIKOFLASH_SRC}")/tagbankhighlightsync.koplugin"}"
: "${ANKIKOFLASH_DST:="$HOME/koreader-dev/plugins/AnkiKoFlash.koplugin"}"
: "${TAGBANKHIGHLIGHTSYNC_DST:="$HOME/koreader-dev/plugins/tagbankhighlightsync.koplugin"}"
# Legacy env names (still accepted)
: "${HIGHLIGHTSYNC_SRC:="$TAGBANKHIGHLIGHTSYNC_SRC"}"
: "${HIGHLIGHTSYNC_DST:="$TAGBANKHIGHLIGHTSYNC_DST"}"

is_wsl() {
    if [ -d /mnt/wslg ]; then
        return 0
    fi
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        return 0
    fi
    if [ -r /proc/version ] && grep -qiE 'microsoft|wsl' /proc/version; then
        return 0
    fi
    return 1
}

wslg_preflight() {
    if ! is_wsl; then
        return 0
    fi
    if [ ! -d /mnt/shared_memory ]; then
        echo "WARNING: /mnt/shared_memory is missing — WSLg may show [WARN: COPY MODE]" >&2
        echo "         in the taskbar and behave poorly on a second GUI launch." >&2
        echo "         Try: wsl --update && wsl --shutdown (then reboot if needed)." >&2
    fi
}

cloudstorage_preflight() {
    local plugin_main="$KOREADER/plugins/cloudstorage.koplugin/main.lua"
    if [ -f "$plugin_main" ]; then
        return 0
    fi
    echo "WARNING: cloudstorage.koplugin missing — TagBankHighlightSync cloud sync will not work." >&2
    echo "         Run: bash setup-emulator-cloud.sh   (from tagbankhighlightsync.koplugin)" >&2
}

run_setup_emulator_cloud() {
    local script="$TAGBANKHIGHLIGHTSYNC_SRC/setup-emulator-cloud.sh"
    if [ ! -f "$script" ]; then
        echo "ERROR: setup-emulator-cloud.sh not found at: $script" >&2
        exit 1
    fi
    KOREADER_DIR="$KOREADER" bash "$script"
}

export_wsl_gui_env() {
    if ! is_wsl; then
        return 0
    fi
    export DISPLAY="${DISPLAY:-:0}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
    # Let SDL3/Mesa use the WSLg d3d12 hardware driver. Forcing llvmpipe here
    # (LIBGL_ALWAYS_SOFTWARE=1, MESA_LOADER_DRIVER_OVERRIDE=llvmpipe,
    # SDL_RENDER_DRIVER=software) triggered WSLg "[WARN:COPY MODE]".
    # To force software rendering, export those vars yourself before launching.
}

resolve_book() {
    local script_dir="$1"
    local book="${2:-}"
    if [ -z "$book" ]; then
        return 0
    fi
    if [ "${book:0:1}" != "/" ]; then
        book="$script_dir/$book"
    fi
    printf '%s' "$book"
}

find_appimage() {
    if [ -n "${KOREADER_APPIMAGE:-}" ]; then
        printf '%s' "$KOREADER_APPIMAGE"
        return 0
    fi
    local candidate
    candidate="$(ls -t "$HOME"/Downloads/koreader-appimage-*.AppImage 2>/dev/null | head -n 1 || true)"
    if [ -n "$candidate" ]; then
        printf '%s' "$candidate"
    fi
}

link_plugin_to_emulator() {
    local dst="$1"
    local name="$2"
    local emulator_plugins="$KOREADER/plugins"
    local link_path="$emulator_plugins/$name"
    if [ ! -d "$emulator_plugins" ]; then
        return 0
    fi
    if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
        rm -rf "$link_path"
    fi
    ln -sfn "$dst" "$link_path"
}

sync_ankikoflash() {
    local src="${1:-$ANKIKOFLASH_SRC}"
    local dst="${2:-$ANKIKOFLASH_DST}"
    if [ ! -d "$src" ]; then
        echo "ERROR: AnkiKoFlash source not found at: $src" >&2
        exit 1
    fi
    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/" \
        --exclude '.git' \
        --exclude 'koreader.log' \
        --exclude 'configuration.lua'
    if [ -f "$src/configuration.lua" ]; then
        cp "$src/configuration.lua" "$dst/"
    elif [ -f "$src/configuration.lua.sample" ]; then
        cp "$src/configuration.lua.sample" "$dst/configuration.lua"
    fi
    link_plugin_to_emulator "$dst" "AnkiKoFlash.koplugin"
    echo "Synced AnkiKoFlash → $dst" >&2
}

sync_tagbankhighlightsync() {
    local src="${1:-$TAGBANKHIGHLIGHTSYNC_SRC}"
    local dst="${2:-$TAGBANKHIGHLIGHTSYNC_DST}"
    if [ ! -d "$src" ]; then
        echo "ERROR: TagBankHighlightSync source not found at: $src" >&2
        echo "       Set TAGBANKHIGHLIGHTSYNC_SRC to your tagbankhighlightsync.koplugin folder." >&2
        exit 1
    fi
    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/" \
        --exclude '.git' \
        --exclude 'koreader.log'
    link_plugin_to_emulator "$dst" "tagbankhighlightsync.koplugin"
    rm -f "$KOREADER/plugins/highlightsync.koplugin"
    echo "Synced TagBankHighlightSync → $dst" >&2
}

# Legacy name used by older start.sh copies
sync_highlightsync() {
    sync_tagbankhighlightsync "$@"
}

sync_both_plugins() {
    if [ ! -d "$KOREADER" ]; then
        echo "ERROR: KOReader emulator not found at: $KOREADER" >&2
        echo "Set KOREADER_DIR to your emulator install." >&2
        exit 1
    fi
    sync_ankikoflash
    sync_tagbankhighlightsync
}

kill_stale_reader() {
    pkill -f './luajit reader.lua' 2>/dev/null || true
    sleep 0.5
}

launch_appimage() {
    local book="${1:-}"
    wslg_preflight
    export_wsl_gui_env

    local appimage
    appimage="$(find_appimage)"
    if [ -z "$appimage" ] || [ ! -f "$appimage" ]; then
        echo "ERROR: No KOReader AppImage found." >&2
        echo "Set KOREADER_APPIMAGE=/path/to/koreader.AppImage, or place a file" >&2
        echo "matching ~/Downloads/koreader-appimage-*.AppImage" >&2
        exit 1
    fi

    if [ ! -x "$appimage" ]; then
        chmod +x "$appimage" || true
    fi

    echo "Launching AppImage: $appimage" >&2
    if is_wsl; then
        echo "NOTE: AppImage from WSL still uses WSLg — COPY MODE may appear in the taskbar." >&2
    fi
    if [ -n "$book" ] && [ -e "$book" ]; then
        exec "$appimage" "$book"
    else
        exec "$appimage"
    fi
}

launch_emulator() {
    local book="${1:-}"

    if [ ! -d "$KOREADER" ]; then
        echo "ERROR: KOReader emulator not found at: $KOREADER" >&2
        echo "Set KOREADER_DIR to your emulator install." >&2
        exit 1
    fi

    wslg_preflight
    if is_wsl; then
        cloudstorage_preflight
    fi
    cd "$KOREADER"
    export LD_LIBRARY_PATH="./libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export_wsl_gui_env
    kill_stale_reader

    if [ -n "$book" ] && [ -e "$book" ]; then
        exec ./luajit reader.lua "$book"
    else
        exec ./luajit reader.lua
    fi
}

default_mode() {
    if is_wsl; then
        printf '%s' appimage
    else
        printf '%s' emulator
    fi
}
