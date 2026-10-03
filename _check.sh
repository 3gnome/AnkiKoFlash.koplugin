#!/bin/bash
# Dev-only syntax/sanity checker (not part of the plugin).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KO="${KOREADER_DIR:-$HOME/koreader-dev/emulator/usr/lib/koreader}"
SRC="${PLUGIN_DIR:-$SCRIPT_DIR}"
LJ="${LUAJIT_BIN:-$KO/luajit}"
fail=0

if [[ "$LJ" == */* ]]; then
    if [ ! -x "$LJ" ]; then
        echo "ERROR: LuaJIT not found or not executable at: $LJ" >&2
        echo "Set LUAJIT_BIN or KOREADER_DIR." >&2
        exit 1
    fi
elif ! command -v "$LJ" >/dev/null 2>&1; then
    echo "ERROR: LuaJIT command not found: $LJ" >&2
    echo "Set LUAJIT_BIN to a LuaJIT executable or command." >&2
    exit 1
fi

echo "=== Parse-check all .lua files (loadfile, parse only) ==="
syntax_fail=0
while IFS= read -r -d '' f; do
    if ! parse_error="$(CHK="$f" "$LJ" -e 'local p=os.getenv("CHK"); local fn,e=loadfile(p); if not fn then io.stderr:write(tostring(e).."\n"); os.exit(1) end' 2>&1)"; then
        echo "SYNTAX ERROR: $f"
        printf '%s\n' "$parse_error"
        syntax_fail=1
        fail=1
    fi
done < <(find "$SRC" -type f -name '*.lua' -not -path '*/.git/*' -print0)
[ "$syntax_fail" -eq 0 ] && echo "All .lua files parse OK"

echo
echo "=== Functional test: note_type_profiles ==="
if ! (
    cd "$SRC" || exit 1
    "$LJ" -e '
package.path = "./?.lua;" .. package.path
local P = require("note_type_profiles")
assert(P.normalize_model_name("Vocabulary") == "Vocabulary", "no legacy remap")
assert(P.normalize_model_name("") == "Vocabulary Card", "empty -> default")
assert(P.is_vocabulary_card("Vocabulary Card") == true, "Vocabulary Card still vocab")
assert(P.is_memorization("Memorization") == true, "Memorization still works")
assert(P.is_vocabulary_compatible("Vocabulary Card") == true, "vocab model compatible")
assert(P.is_vocabulary_compatible("Memorization") == false, "mem model not vocab compatible")
assert(P.profile_type("Vocabulary Card") == "vocabulary", "profile type vocabulary")
assert(P.profile_type("Basic") == "basic", "profile type basic")
print("note_type_profiles: all assertions passed")
'
); then
    echo "FAILED: note_type_profiles"
    fail=1
fi

echo
echo "=== Functional test: plugin_constants ==="
if ! (
    cd "$SRC" || exit 1
    "$LJ" -e '
package.path = "./?.lua;" .. package.path
local C = require("plugin_constants")
assert(C.PREVIOUS_CARDS_FILE == nil, "legacy constant removed")
assert(C.LEGACY_CARDS_FILE == nil, "legacy constant removed")
assert(C.CARDS_FILE == "ankikoflash_cards.json", "cards file intact")
print("plugin_constants: OK")
'
); then
    echo "FAILED: plugin_constants"
    fail=1
fi

echo
echo "=== Specs ==="
if ! (
    cd "$SRC" || exit 1
    "$LJ" spec/run_tests.lua
); then
    echo "FAILED: specs"
    fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "All checks passed"
else
    echo "One or more checks failed"
fi

exit "$fail"
