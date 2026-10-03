#!/bin/bash
# Reset Alice to clean copy (PC only). Run from WSL:
#   bash scripts/reset_alice.sh
#
# Set paths via environment (edit in LOCAL_DEV.md or export before running):
#   WEBDAV_ROOT  WebDAV / Obsidian root
#   ANKI_REPO    This plugin directory (default: repo root)
#   TAGBANK_REPO Tag Bank plugin directory
#   DESKTOP_KO   Optional desktop KOReader tree

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANKI_REPO="${ANKI_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WEBDAV="${WEBDAV_ROOT:?Set WEBDAV_ROOT to your WebDAV/Obsidian root}"
LIBRARY="$WEBDAV/library"
DESKTOP_KO="${DESKTOP_KO:-}"
EMULATOR_KO="$HOME/koreader-dev/emulator/usr/lib/koreader"
TAGBANK="${TAGBANK_REPO:-$(dirname "$ANKI_REPO")/tagbankhighlightsync.koplugin}"
LJ="$EMULATOR_KO/luajit"

echo "=== 1. AnkiConnect: delete Alice notes (if Anki running) ==="
ANKI_URL="${ANKI_URL:-http://127.0.0.1:8765}"
delete_anki_query() {
    local query="$1"
    local payload resp ids_json
    payload=$(QUERY="$query" python3 - <<'PY'
import json, os
print(json.dumps({"action": "findNotes", "version": 6, "params": {"query": os.environ["QUERY"]}}))
PY
)
    resp=$(curl -sf -X POST "$ANKI_URL" -H "Content-Type: application/json" -d "$payload" 2>/dev/null) || return 1
    ids_json=$(python3 - <<'PY' "$resp"
import json, sys
d = json.loads(sys.argv[1])
print(json.dumps(d.get("result") or []))
PY
)
    if [ "$ids_json" = "[]" ]; then
        echo "  No notes for query: $query"
        return 0
    fi
    payload=$(IDS="$ids_json" python3 - <<'PY'
import json, os
ids = json.loads(os.environ["IDS"])
print(json.dumps({"action": "deleteNotes", "version": 6, "params": {"notes": ids}}))
PY
)
    curl -sf -X POST "$ANKI_URL" -H "Content-Type: application/json" -d "$payload" >/dev/null \
        && echo "  Deleted notes for: $query" || echo "  deleteNotes failed for: $query"
}

if curl -sf -X POST "$ANKI_URL" -H "Content-Type: application/json" \
    -d '{"action":"version","version":6}' >/dev/null 2>&1; then
    delete_anki_query "deck:English::Koreader::Alice's Adventures in Wonderland" || true
    delete_anki_query "deck:English::Koreader::Alice*" || true
    delete_anki_query "Source:*Alice's Adventures in Wonderland*" || true
else
    echo "  AnkiConnect not reachable at $ANKI_URL — skip Anki delete (purge local cards anyway)"
fi

echo "=== 2. Purge Alice from ankikoflash_cards.json ==="
filter_cards() {
    local path="$1"
    [ -f "$path" ] || return 0
    python3 - "$path" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    cards = json.load(f)
if not isinstance(cards, list):
    sys.exit(0)
needle = "Alice's Adventures in Wonderland"
kept = [c for c in cards if needle not in (c.get("book_title") or "")]
removed = len(cards) - len(kept)
with open(path, "w", encoding="utf-8") as f:
    json.dump(kept, f, ensure_ascii=False)
print(f"  {path}: removed {removed}, kept {len(kept)}")
PY
}
filter_cards "$DESKTOP_KO/ankikoflash_cards.json"
filter_cards "$EMULATOR_KO/ankikoflash_cards.json"
for f in "$DESKTOP_KO/ankikoflash_recent_sent.json" "$EMULATOR_KO/ankikoflash_recent_sent.json"; do
    filter_cards "$f" 2>/dev/null || true
done

echo "=== 3. Delete alice.epub + sidecars ==="
rm -f "$ANKI_REPO/alice.epub"
rm -rf "$ANKI_REPO/alice.sdr"
rm -f "$DESKTOP_KO/plugins/AnkiKoFlash.koplugin/alice.epub"
rm -rf "$DESKTOP_KO/plugins/AnkiKoFlash.koplugin/alice.sdr"
rm -f "$EMULATOR_KO/cache/cr3cache/alice.epub."*.cr3 2>/dev/null || true

echo "=== 4. Delete WebDAV alice.sdr.json ==="
rm -f "$WEBDAV/alice.sdr.json" "$WEBDAV/alice.sdr.json.sync"

echo "=== 5. Purge Alice library files ==="
rm -f "$LIBRARY/books/alice.sdr.md" "$LIBRARY/books/alice.sdr.md.sync"
rm -f "$LIBRARY/tags/alice.md" "$LIBRARY/tags/alice.md.sync"
while IFS= read -r f; do
    base=$(basename "$f" .md)
    rm -f "$f" "$f.sync" "$LIBRARY/quotes/images/${base}.png" "$LIBRARY/quotes/images/${base}.png.sync"
done < <(grep -rl 'sidecar: alice.sdr' "$LIBRARY/quotes" 2>/dev/null || true)

EMU_LIB="$EMULATOR_KO/highlight_sync_library"
rm -f "$EMU_LIB/books/alice.sdr.md" "$EMU_LIB/books/alice.sdr.md.sync" 2>/dev/null || true
rm -f "$EMU_LIB/tags/alice.md" "$EMU_LIB/tags/alice.md.sync" 2>/dev/null || true
while IFS= read -r f; do
    base=$(basename "$f" .md)
    rm -f "$f" "$f.sync" "$EMU_LIB/quotes/images/${base}.png" 2>/dev/null || true
done < <(grep -rl 'sidecar: alice.sdr' "$EMU_LIB/quotes" 2>/dev/null || true)

echo "=== 6. Regenerate library from remaining JSON ==="
"$LJ" "$TAGBANK/spec/regen_library_from_json.lua" "$WEBDAV" "$LIBRARY"

echo "=== 7. Download fresh Alice.epub ==="
curl -Lf -o "$ANKI_REPO/alice.epub" "https://www.gutenberg.org/ebooks/11.epub.noimages"
ls -la "$ANKI_REPO/alice.epub"

echo "=== Done ==="
