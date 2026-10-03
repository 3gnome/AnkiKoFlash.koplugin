# Changelog

This file records notable changes. Historical releases are documented in
[`docs/release-notes-v1.0.9.md`](docs/release-notes-v1.0.9.md) and
[`docs/release-notes-v1.1.1.md`](docs/release-notes-v1.1.1.md).

## Unreleased

### Fixed (P0 — data loss / regressions)
- Bounded 412-conflict retry — new `anki_retry.lua` caps retries instead of looping
- Corrupt/empty remote queue JSON no longer treated as "no cards" (recoverable persistence)
- Etymology no longer silently dropped for note types without an `Etymology` field (fallback)
- Batch send + trailing `sync_collection` wrapped in `UiBusy` (no more frozen UI)

### Fixed (P1 — correctness)
- Default placeholder URL (`192.168.x.x`) treated as unconfigured
- `post()` handles non-object JSON responses without crashing
- Network errors no longer trigger a redundant round trip
- Multi-pass HTML entity decoding and case-insensitive `<br>` handling
- Etymology fallback inspects all dictionary results; `capitalize_first` no longer mangles camelCase
- Multibyte UTF-8 truncation fixed (cuts on character boundary)
- `getReadablePath` uses a colon, not a dot
- Successful `addNote` no longer reported as "failed" — `send_card_with_status` now detects a
  JSON-`null` error field the same way the rest of `anki_sync.lua` does (KOReader's LuaJSON decodes
  `null` to a sentinel function, not Lua `nil`, so `result.error == nil` was never true on success)

### Added / improved (P2 — UX)
- "Save only (skip send to Anki)" toggle in the hub menu — one-click local save with no network
  attempt, keeping auto note type, dictionaries, and default deck
- Deck / note-type pickers: search + filter
- Per-card review/edit before batch send
- Undo for destructive deletes; offline queue status badge
- History written before queue deletion; accurate `failed to send (saved locally)` counts
- "Test Connection" wrapped in `UiBusy` (non-blocking)

### Polish (P3)
- Emoji labels replaced with plain text; offline picker subtitles clarified
- Sentence splitting protects abbreviations (`Mr.`, `e.g.`) and decimals (`3.14`)
- Card templates in `docs/anki-vocabulary-card.md` and `docs/anki-memorization.md` are now link-only
  pointers to the single source of truth in `docs/desktop/*-anki-templates.txt`

### Docs / hygiene
- Removed stale `(Multi-Line)` / `(plugin v2)` template references
- Added `pre-commit-privacy-check.sh` and a pre-commit/privacy guard step (see `CONTRIBUTING.md`)
- `.shift/` added to `.gitignore`; `dev-lib.sh` no longer defaults `KOREADER_CAPTURE_DIR` to a personal path
