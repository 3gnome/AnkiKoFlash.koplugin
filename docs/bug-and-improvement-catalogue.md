# Bug & Improvement Catalogue — AnkiKoFlash + TagBankHighlightSync

> Assembled 2026-10-02 from a 30-minute parallel subagent scan (4 explore agents) plus direct verification.
> Scope: Anki ↔ AnkiKoFlash interface, UI, features; expanded to tagbankhighlightsync.koplugin; documentation for both.
> IDs: **A###** = AnkiKoFlash, **T###** = TagBankHighlightSync. Phases = suggested fix order.

---

## How to read this

- **P0 Critical** — functional regressions or data loss. Fix first.
- **P1 High** — correctness bugs with real user-visible impact.
- **P2 Medium** — UX gaps / feature improvements / robustness.
- **P3 Low** — polish / consistency.
- Every item carries `file:line` evidence. Cross-plugin items are flagged **CROSS**.

---

## P0 — Critical (regressions + data loss)

### T01 — CROSS — TagBank can no longer detect AnkiKoFlash (functional regression)
- `tagbankhighlightsync.koplugin/plugin_peers.lua:6-16` probes `"ankikooai"` (3×) and `ui.ankikooai`.
- AnkiKoFlash registers as `"ankikoflash"` (`AnkiKOFlash.koplugin/plugin_constants.lua:4`, `_meta.lua`).
- **Symptom:** `is_ankikooai_available()` always returns `false`. The Anki-branded orange/green quote-library filter labels in Settings never appear even when both plugins are installed. **VERIFIED.**
- **Fix:** rename all `"ankikooai"` → `"ankikoflash"` and `ui.ankikooai` → `ui.ankikoflash`; rename `is_ankikooai_available` → `is_ankikoflash_available`; update `spec/plugin_peers_spec.lua` mocks.

### T02 — Unbounded 412-conflict retry loop can hang the device
- `cloudstorage_compat.lua:192-258` — `while code_response == 412 do` re-downloads/re-merges/re-uploads with no retry cap and no backoff; `provider.run` is synchronous/blocking.
- **Symptom:** device UI freezes indefinitely during a sync; no timeout or error surfaces.
- **Fix:** bounded retry (max 3) with a small `scheduleIn` delay, then fail with `phase="conflict"`.

### T03 — Corrupt/empty remote JSON treated as "no highlights" → silent data loss
- `main.lua:421` and `main.lua:780` ignore the `ok` (2nd) return of `read_json_file`, treating invalid remote JSON as `{}`.
- `merge.lua:134-138` then treats a remote-only highlight as "deleted remotely" and drops it; local file is uploaded over the corrupt remote and reported **SUCCESS**.
- **Symptom:** a single truncated `*.sdr.json` silently deletes remote-only highlights.
- **Fix:** hard-error when `ok == false` for the income file; abort merge (or back up corrupt remote first).

### T04 — Tag merge is a pure union — tag deletions never propagate
- `merge.lua:140-148` → `tags.lua:120-136` computes `winner ∪ local ∪ server`.
- **Symptom:** removing a tag on device A is undone when device B (still holding the tag) syncs. Core "tag bank" correctness defect.
- **Fix:** track per-tag removals against the `last_sync` baseline (or store tombstones) instead of a naive union.

### A01 — Etymology silently dropped for note types without an `Etymology` field
- `card_fields.lua:259-261` returns an `etymology` role but, unlike `context` (`:317-321`), it has **no fallback**.
- **Symptom:** choosing any note type without an `Etymology`/`Origin`/`Root`/`Derivation` field (e.g. "Basic") silently discards the looked-up etymology with no warning.
- **Fix:** append etymology to the definition field when no etymology-named field exists (mirror the context fallback), or surface a notice.

### A02 — Batch send + trailing `sync_collection` block the UI (no Trapper)
- `anki_sync.lua:17` (`SYNC_TIMEOUT = 120`), `anki_sync.lua:315-333`; `card_manager.lua:380-450` (batch loop) and `card_manager.lua:482` (finish).
- **Symptom:** "Send pending to Anki" and memorization batch run synchronous HTTP outside `UiBusy`/Trapper; the trailing `sync` can block up to 120 s. Freezes the e-ink reader.
- **Fix:** run the whole batch in `UiBusy.run`, and defer/lower the trailing `sync_collection` timeout.

---

## P1 — High (correctness)

### A03 — Default placeholder URL treated as configured
- `configuration.lua:6` ships `url = "http://192.168.1.100:8765"`; guards only reject literal `192.168.x.x` (`card_manager.lua:87-89`, `poetry_memorize.lua:562`).
- **Symptom:** fresh installs attempt HTTP to a dead LAN IP with retries instead of prompting for setup.
- **Fix:** treat `192.168.1.100` (or any `192.168.1.x`/`localhost`) as unset, or blank the default.

### A04 — `post()` can crash on non-object JSON responses
- `anki_sync.lua:88-89` returns the raw `json.decode` result; `:107` then reads `result.error` with no `type(result)=="table"` guard.
- **Symptom:** proxy/captive-portal/misconfigured responses (`[]`, `42`, `"ok"`) raise "attempt to index …".
- **Fix:** validate `type(result) == "table"` after decode and return a typed "unexpected response" error.

### A05 — Network errors trigger a redundant round trip + misleading "outcome uncertain"
- `anki_sync.lua:536-555`; `is_network_error` includes "Cannot reach Anki" (`anki_retry.lua:37-39`).
- **Symptom:** unreachable Anki doubles the wait and shows an alarming "outcome uncertain" message.
- **Fix:** short-circuit verification on unreachable/refused/timeout; keep verify only for genuine duplicate errors.

### A06 — Incomplete HTML entity decoding corrupts card text
- `dictionary_lookup.lua:34-44` and `etymology_lookup.lua:26-34` (duplicated `strip_html`) only decode `&nbsp;&amp;&lt;&gt;&quot;` and decimal `&#N;` in ASCII 32–126.
- **Symptom:** `&mdash;`, `&rsquo;`, `&eacute;`, `&#x2014;`, `&#8217;` leak literally or vanish. Wiktionary dictionaries are full of these.
- **Fix:** centralize into one decoder with a named-entity table + `&#x…;` + widened decimal range.

### A07 — Etymology fallback only inspects the FIRST dictionary result
- `etymology_lookup.lua:97-113` — `first_definition` returns the first non-empty definition, then `extract_etymology_from_html` scans only it.
- **Symptom:** when the first enabled dictionary lacks an `Etymology` heading but a later one has it, the field stays empty.
- **Fix:** iterate all results and extract from the first definition containing an `Etymology` heading.

### A08 — `capitalize_first` mangles camelCase headwords
- `main.lua:130-132` (`s:gsub("^%l", string.upper)`).
- **Symptom:** `iPhone`→`IPhone`, `eBay`→`EBay`, `iOS`→`IOS` on card fronts.
- **Fix:** capitalize only when the word is otherwise all-lowercase.

### A09 — Truncation cuts multibyte UTF-8 mid-character
- `dictionary_lookup.lua:53` (`#text > MAX → sub(1, MAX)`), also `etymology_lookup.lua:36`, `preview_text`, `main.lua:125`.
- **Symptom:** garbled last character on long non-ASCII definitions.
- **Fix:** truncate on a UTF-8 lead-byte boundary.

### T05 — `getReadablePath` called with dot instead of colon
- `main.lua:1728` — `cs.getReadablePath(server)` (adjacent `:1726` uses `cs:getServerNameType(server)` correctly).
- **Symptom:** Cloud-folder dialog errors or shows a wrong/blank path.
- **Fix:** change to `cs:getReadablePath(server)`.

### T06 — Merge sync path lost socket timeouts (regression vs stock cloudstorage)
- `cloudstorage_compat.lua:158-314` reimplements `cls:sync` without `socketutil:set_timeout(...)` (present in `:365` `uploadBinaryFile`, `:425` `pushSyncFile`).
- **Symptom:** large JSON/export uploads fail spuriously or hang on default timeout.
- **Fix:** set/reset `FILE_BLOCK_TIMEOUT`/`FILE_TOTAL_TIMEOUT` around download/upload.

### T07 — `write_json_file` fallback is non-atomic
- `main.lua:211-231` falls back to truncate-in-place `io.open(path,"w")` when `os.rename` fails.
- **Symptom:** interrupted sync leaves a half-written sidecar → feeds T03.
- **Fix:** remove-then-rename, or write a backup before the in-place fallback.

### T08 — Sync-all skips books with zero syncable annotations → deletions don't propagate
- `main.lua:478-482` (`if #filtered == 0 then on_done(true); return`), `sync_all_books.lua:76-80`.
- **Symptom:** deleted highlights reappear on another device after "Sync all books".
- **Fix:** push an empty `{}` payload when annotations exist but none are syncable.

### T09 — Concurrent-sync guard gaps
- `main.lua:1310-1313` guards `is_syncing`, but `batchSyncCurrentFolder` (`:1751-1815`) and `schedule_close_push` (`sync_background.lua:159-206`) do not.
- **Symptom:** interleaved syncs → merge conflicts, spurious 412s, stuck progress.
- **Fix:** route batch/close-push through the same `is_syncing` gate.

### T10 — `_sync_now_target_ann` can leak on early-return
- `main.lua:1242-1244` set, then early return at `:1310-1313` if already syncing; cleared only in `clear_transient_sync_state`.
- **Symptom:** a later sync may prioritize a stale target annotation.
- **Fix:** clear on the early-return path too.

---

## P2 — Medium (UX / features / robustness)

### A10 — Stale AI-era wiring still live (`target_language` + Cambridge URL)
- `main.lua:87-89` promotes `target_language`; `plugin_menu.lua:18` lists it; `main.lua:134-139,263` feed a Cambridge Dictionary URL as the `Source` fallback.
- `target_language` is **not** in the `card_fields.lua` scrub list.
- **Fix:** remove `target_language` + `cambridge_url` (product is dictionary-only, no network).

### A11 — History written before queue deletion
- `card_reconcile.lua:63-72` — `record_recent_sent` before `delete_matching_card`; failed history write silently loses visibility.
- **Fix:** delete first then write history, or re-queue with a "sent, pending history" marker.

### A12 — `failed` counter masks send failures as "saved locally"
- `highlight_inbox.lua:491-509` — auto-send failure falls into `done = done + 1`.
- **Fix:** track send failures separately and report "N failed to send (saved locally)".

### A13 — "Test Connection" blocks the UI
- `settings_viewer.lua:1057-1060` calls `AnkiSync.test_connection` directly (no `UiBusy.run`).
- **Fix:** wrap in `UiBusy.run("Testing connection…", …)`.

### A14 — Deck / note-type pickers need search + filter
- `deck_picker.lua`, `note_type_picker.lua` render the full sorted list with no search.
- **Fix:** add search box; keep "Enter manually…" fallback. Effort M.

### A15 — Per-card review/edit before batch send
- `card_manager.lua` "Send All Unsent" sends with no preview.
- **Fix:** wire the existing single-card Edit flow into a pre-send review. Effort M.

### A16 — Undo for destructive deletes
- `selectable_menu.lua` + `card_manager.lua` — "Clear All Cards"/"Delete Selected"/"Remove from queue" have only a confirm, no undo. Effort M.

### A17 — Offline queue status badge
- `plugin_menu.lua` shows "Send pending (N)" but no indication of *why* (offline vs failed vs not-attempted). Effort S.

### T11 — `markLibrarySynced` persists without flushing
- `main.lua:947-958` saves but never `doc_settings:flush()` (contrast `persistMergedToDocSettings` `:409`).
- **Fix:** add `flush()`.

### T12 — Single-highlight "Sync now" triggers a full book merge
- `main.lua:1235-1244` (`syncNow`) merges the whole book, importing unrelated remote changes.
- **Fix:** allow library-only upload for a single highlight. Effort M.

### T13 — Progress + cancel for "Sync all books"
- `main.lua:514-631` shows only a per-book label; no cancel; long histories block. Effort M.

### T14 — Batch-sync confirmation before overwrite
- `main.lua:1751-1815` raw-pushes (no merge) and can clobber remote changes. Effort S.

### T15 — Tag-bank integrity check (orphan tag ids)
- `tag_bank.lua` — deleting/renaming nodes leaves applied `highlight_sync_tags` ids unresolved. Effort M.

---

## P3 — Low (polish / consistency)

- **A18** — `card_viewer.lua:193` uses emoji `"✏️ Edit"` (renders as tofu on e-ink). Replace with plain "Edit".
- **A19** — `card_viewer.lua:339` hardcoded gray "Study the topic." placeholder is dead UI. Remove or make configurable.
- **A20** — `settings_viewer.lua:800-805` has both "Back" and "Close without saving" doing the same thing. Use one "Cancel"/"Discard".
- **A21** — cached-list fallback subtitle (`deck_picker.lua:138-139`, `note_type_picker.lua:133-134`) too subtle; users may pick a stale deck.
- **A22** — sentence splitter (`poetry_memorize.lua:340-372`) doesn't guard abbreviations (`Mr.`, `e.g.`, `St.`) or decimals (`3.14`). Effort M.
- **A23** — `<br>` handling case-sensitive in one path (`dictionary_lookup.lua:30`) vs `[bB][rR]` in the newline branch.
- **A24** — `normalize_entry` falls back on empty `raw.word` (empty string is truthy in Lua), `dictionary_lookup.lua:105`.
- **A25** — placeholder-URL pattern case-sensitive: `"192%.168%.x%.x"` (`poetry_memorize.lua:561,814`) vs plain `"192.168.x.x"` (`card_manager.lua:89`); uppercase `X` not caught.
- **T16** — `main.lua:1296-1299` reports "Configure Cloud folder…" even when the real reason is "already synced".
- **T17** — close-sync deferred toasts (`sync_background.lua:176-202`) use three different wordings.
- **T18** — "Cloud storage" / "Cloud Storage" / "Cloud folder" used interchangeably (`main.lua:1653`, README, `settings_menu.lua`).

---

## Documentation update inventory

### AnkiKoFlash (`AnkiKOFlash.koplugin/`)

| File | Issue | Update |
|------|-------|--------|
| `README.md` | 7 image links broken — `docs/images/` contains only `README.md` | Add screenshots or comment out image tables |
| `docs/images/README.md` | filename list misses `deck-picker.png` + 3 memorization images | Sync list to README |
| `docs/anki-memorization.md:308` | stale retired `wiki_deck` key | Remove; document `vocabulary_deck`/`memorize_parent_deck` |
| `docs/anki-memorization.md` (Parts 2–6) | template/CSS drift vs `docs/desktop/memorization-anki-templates.txt` | Link-only, or paste current templates |
| `docs/anki-vocabulary-card.md` (Parts 2–4) | back template omits `<script>` POS highlighter; old CSS | Align with `docs/desktop/vocabulary-card-anki-templates.txt` |
| `anki-memorization-setup.txt` / `docs/desktop/memorization-anki-templates.txt` | stale "(Multi-Line)" and "v2" | Drop both |
| `docs/webdav-setup-windows.md:202` | "API keys" (removed feature) | Remove "API keys" |
| `LOCAL_DEV.md:10` | references nonexistent `.cursor/rules/ankikoflash-dev.mdc` | Fix or remove |

### TagBankHighlightSync (`tagbankhighlightsync.koplugin/`)

| File | Issue | Update |
|------|-------|--------|
| `plugin_peers.lua` | `"ankikooai"` id (see T01) | `"ankikoflash"` + rename fn |
| `spec/plugin_peers_spec.lua` | asserts stale id | Update mocks |
| `settings_menu.lua:282` | "AnkiKOAi … sent **wiki** card" | "AnkiKoFlash … sent card" |
| `README.md` | `AnkiKOAi` + `github.com/3gnome/AnkiKOAi.koplugin` | `AnkiKoFlash` + correct URL |
| `docs/companion-ankikooai.md` | retired name throughout; filename | Rename → `docs/companion-ankikoflash.md`; s/AnkiKOAi/AnkiKoFlash/g |
| `docs/README.md` | links `companion-ankikooai.md` | Update filename + name |
| `docs/getting-started.md` | `AnkiKOAi`, "Wiki/Vocab/Mem" | Rename + drop "Wiki" |
| `docs/webdav-setup-windows.md` | links AnkiKOAi guide URL | Point to AnkiKoFlash |
| `docs/publishing.md` | AnkiKOAi cross-links | Update URL + name |
| `docs/release-notes-v0.9.1.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LOCAL_DEV.md`, `LOCAL_DEV.md.sample` | `AnkiKOAi` / "Wiki/Vocab/Mem" | Rename + drop "Wiki" |
| `start.sh`, `dev-start.sh` | `ANKIKOOAI_SRC` + `AnkiKOAi.koplugin` path | `ANKIKOFLASH_SRC` / `AnkiKoFlash.koplugin` (AnkiKoFlash's `dev-lib.sh` already uses `ANKIKOFLASH_SRC`) |
| **Cross-repo** `AnkiKOFlash/docs/tag-bank-companion.md:31` | links TagBank `docs/companion-ankikoflash.md` (does not exist) | Resolves after TagBank renames; otherwise revert link |

---

## Cross-plugin integration — summary

- The interface is **one-directionally broken**: AnkiKoFlash correctly detects TagBank (`plugin_peers.lua` checks `TagBankHighlightSync`/`tagbankhighlightsync`), but TagBank probes the retired `"ankikooai"` and can never see AnkiKoFlash (T01).
- Both sides agree on semantics (orange = pending, green = confirmed; TagBank owns JSON sync + quote library; AnkiKoFlash exposes "Sync All Highlights"), but disagree on **naming/links**: TagBank still ships the `AnkiKOAi` brand, "wiki card" wording, and a `github.com/3gnome/AnkiKOAi.koplugin` URL that will 404.

---

## Test / coverage gaps (TagBank)

- No dedicated spec: `main.lua` (sync orchestration, reload, close-push), `settings_menu.lua` (orange/green peer branching — would have caught T01), `tag_dialog.lua`, `insert_menu.lua`, `insert_menu_cloudstorage.lua`, `_meta.lua`, `dev-capture.lua`.
- `spec/validate_webdav_library.lua` and `spec/regen_library_from_json.lua` are manual-only; `_check.sh` only parse-checks (does not run `run_tests.lua`); no CI (`.github/` absent).
- Recommend: a `plugin_peers`/`settings_menu` spec asserting the correct peer id (rename-purity equivalent to AnkiKoFlash's `rename_purity_spec.lua`).

---

## Already completed this session (context, not open items)

- Note-type picker made cache-first (menu opens ~113 ms, was multi-second).
- Dual-dictionary pipeline verified: `Definition` from `reader.dict EN`, `Etymology` from `Etymology (Wiktionary)`.
- Desktop Anki note type updated: `Etymology` field added (order 3), back template `{{#Etymology}}` section + `id="ankikoflash-def"` rename, `.etymology` CSS.
- `configuration.lua` (local, gitignored) got an active etymology default; `configuration.lua.sample` already documents it as a comment.
- Full AnkiKoFlash spec suite: 709 passed, 0 failed.
