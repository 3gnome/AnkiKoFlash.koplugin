# Plugin configuration

How to connect the plugin to AnkiConnect and your decks.

## Two places settings live

| Source | When to use |
|--------|-------------|
| **`configuration.lua`** | Initial setup on PC; version-control a **sample** only (`configuration.lua.sample`) |
| **On-device Settings UI** | Kobo/Kindle — saved to `ankikoflash_settings.json` in KOReader's data dir |

On-device settings **override** `configuration.lua` for Anki and card defaults after you save them once.

`configuration.lua` is gitignored — never commit LAN URLs or local settings.

Settings edits are transactional: the plugin writes the complete candidate settings file before adopting the change in memory. If storage is full or unwritable, it reports the failure and keeps the previously saved value.

### Create local config

```bash
cp configuration.lua.sample configuration.lua
```

Edit the URL and defaults, then copy the plugin folder to the device.

---

## Settings UI map

Open from **AnkiKoFlash → Settings** or the plugin hub menu.

**Gray help rows:** Settings menus use gray text for informational rows. The subtitle says *Tap gray rows for help.* — tap any gray row for a detailed explanation. Normal rows change settings or open submenus.

### Main screen

| Setting | Description |
|---------|-------------|
| **Card defaults…** | Per card type: note type and default deck (from Anki), one-tap send, dictionary |
| **Anki connection…** | AnkiConnect URL, sync after send, test connection |
| **Tags…** | Enable tags and edit tag list (tap **About tags** for help) |
| **Memorization options…** | Split/context/batch behavior (not deck or note type) |
| **Sync…** | Send pending cards when WiFi is on (every **20 minutes**, silent), cloud backup |

### View All Highlights

Not a Settings screen — opened from the **highlight menu** (**View All Highlights**) or **AnkiKoFlash hub → View All Highlights** (same checklist as **Highlights and Cards → Highlights to Anki**).

| Action | Description |
|--------|-------------|
| **Switch book…** | Open highlights from any book in reading history (live annotations on the open book; sidecar on others) |
| **Sync All Highlights** | When [Tag Bank Highlight Sync](https://github.com/3gnome/tagbankhighlightsync.koplugin) is installed — cloud sync for all books in history |
| Checklist | Highlights in the selected book (any color) |
| **Delete Selected Highlights** | Open book only — removes highlights and pending cards matching the exact document and structural highlight position (legacy positionless rows use same-document phrase fallback) |
| Batch send | Switch mode (Vocabulary / Memorization) and send selected highlights to Anki |

After a successful background send, orphan **orange** vocabulary/memorization highlights may be removed automatically on next plugin load (`highlight_cleanup.lua`).

### Card defaults

| Submenu | Settings |
|---------|----------|
| **Vocabulary Card…** | Note type, default deck, hub menu label, preferred dictionary, etymology dictionary, **One-tap send (Vocabulary)** |
| **Memorization Card…** | Note type, parent deck, **One-tap send (Memorization)**, quick highlight button, skip hub submenu when auto-send |
| **Where cards go…** | Subdeck-by-book, live deck preview, per-book deck overrides (Vocabulary only) |
| **Deck picker shortcuts…** | Favorite decks for manual send; recent decks (read-only) |

**One-tap send** uses each card type's configured default deck (not the last deck you picked manually). Turn it on per card type under **Card defaults**.

**Save only** is a toggle in the **AnkiKoFlash hub menu** (not Settings): when ON, Vocabulary Card skips the note-type and dictionary pickers and uses the default deck, but saves locally and never attempts to reach Anki. It takes precedence over one-tap send, so cards stay in **My Cards** until you send them manually.

When **Skip hub submenu when auto-send** is ON and one-tap send is ON for a card type, the AnkiKoFlash hub goes straight to that action (no "Create…" submenu).

### Settings migration

Migrations are additive and preserve existing card schemas:

- **Send to Anki after generate** becomes the two per-type **One-tap send** toggles.
- Legacy `memorize_auto_send` becomes `auto_send_memorization`.
- Retired legacy settings (including any provider/API-key values) are scrubbed from saved settings on load.
- Missing or invalid `max_memorization_steps` becomes 80; an existing positive value is retained.
- Legacy accepted `sent_to_anki` queue rows are removed only after their cleaned queue is durably saved. A failed cleanup is retried on the next startup.

A migration is marked complete only after a successful write. If saving fails, the plugin reports it and retries later.

---

## AnkiConnect

| Requirement | Detail |
|-------------|--------|
| Anki desktop | Must be running on the PC |
| Add-on | AnkiConnect — install code `2055492159` |
| Port | Default `8765` |
| URL from e-reader | `http://192.168.x.x:8765` — **not** `localhost` or `127.0.0.1` |

Test with **Test Connection** under **Anki connection**. If it fails: check firewall, Wi‑Fi isolation (guest networks often block device-to-PC), and that Anki is in the foreground at least once after install.

### Deck resolution (Vocabulary)

1. Start from the card type's default deck (**Card defaults → Vocabulary Card**)
2. If **per-book mapping** exists for `book_title`, use that deck instead (**Card defaults → Where cards go… → Book overrides**)
3. If **Append book title to deck name** is ON (**Where cards go…**), append `::Book Title` to the parent segment of the base deck

Example: default `English::Koreader`, book *Moby-Dick* → `English::Koreader::Moby-Dick`

With a book override to `English::Literature`, subdeck ON → `English::Moby-Dick` (parent is the first `::` segment of the override).

---

## Vocabulary (`anki` section)

```lua
anki = {
    url   = "http://192.168.1.100:8765",
    deck  = "English::Koreader",  -- legacy fallback; prefer vocabulary_deck
    vocabulary_deck = "English::Koreader",
    vocabulary_model = "Vocabulary Card",
    memorize_parent_deck = "Memorize",
    max_memorization_steps = 80,
    tags  = { "KOReader" },
    sync_after_send = true,
    auto_send_vocabulary = false,
    save_only_vocabulary = false,
    auto_send_memorization = false,
    auto_send_skip_hub_submenu = false,
    vocabulary_preferred_dictionary = "reader.dict EN",
    etymology_preferred_dictionary = "Etymology (Wiktionary)",
},
```

| Key | Purpose |
|-----|---------|
| `url` | AnkiConnect endpoint |
| `vocabulary_deck` | Default deck for **Vocabulary Card** sends |
| `deck` | Legacy fallback when per-type deck keys are unset |
| `vocabulary_model` | Note type for **Vocabulary Card** |
| `memorize_parent_deck` | Parent deck for memorization subdecks |
| `max_memorization_steps` | Confirmation threshold for large memorization passages |
| `auto_send_vocabulary` / `auto_send_memorization` | One-tap send per card type |
| `save_only_vocabulary` | Hub-menu **Save only** toggle: skip pickers and save locally without sending (vocabulary only) |
| `auto_send_skip_hub_submenu` | Flatten hub menu when one-tap send is ON for that type |
| `vocabulary_preferred_dictionary` | StarDict name for vocabulary (definition) lookups — chosen via the installed-StarDict picker |
| `etymology_preferred_dictionary` | StarDict name for the offline etymology lookup (e.g. `Etymology (Wiktionary)`) — chosen via the installed-StarDict picker |
| `tags` | Tags on every vocab note |
| `sync_after_send` | Push to AnkiWeb after successful send |

On-device equivalents: same names without the `anki.` prefix in the saved settings file.

---

## Memorization (`memorize` section)

```lua
memorize = {
    parent_deck             = "Memorize",
    model                   = "Memorization",
    context_lines           = 3,
    context_cumulative      = false,
    max_words_per_unit      = 7,
    auto_create_deck        = true,
    include_full_recitation = true,
    force_verse_lines       = false,
    show_split_preview      = false,
    replace_duplicates      = false,
    merge_batch             = false,
    auto_send               = false,
    auto_save_on_fail       = false,
    tags                    = { "KOReader", "memorization" },
},
```

**Deck and note type** are set under **Settings → Card defaults → Memorization Card**. **Behavior** (context lines, verse split, batch merge, etc.) is under **Memorization options**.

On-device keys for **Card defaults**: `vocabulary_deck`, `vocabulary_model`, `vocabulary_card_hub_label`, `memorize_parent_deck`, `memorize_model`, `auto_send_vocabulary`, `save_only_vocabulary`, `auto_send_memorization`, `memorize_quick_highlight_button`, `auto_send_skip_hub_submenu`, `vocabulary_preferred_dictionary`, `etymology_preferred_dictionary`.

On-device keys for **Where cards go**: `subdeck_by_book`, `per_book_decks`.

On-device keys for **Deck picker shortcuts**: `favorite_decks`, `recent_decks` (recent is auto-updated on manual send).

On-device keys for **Memorization options**: `memorize_context_lines`, `memorize_context_cumulative`, `memorize_max_words`, `max_memorization_steps`, `memorize_include_full_recitation`, `memorize_force_verse_lines`, `memorize_show_split_preview`, `memorize_replace_duplicates`, `memorize_merge_batch`, `memorize_auto_save_on_fail`.

`max_memorization_steps` defaults to 80. It is a confirmation threshold, not a truncation limit: larger passages require explicit confirmation. Generated Anki notes are sent in groups of at most 50. A partially confirmed passage remains pending until every note is sent or verified.

See [Anki: Memorization deck](anki-memorization.md) for tuning prose vs poetry.

---

## Etymology dictionary

AnkiKoFlash fills the **Etymology** field on Vocabulary Cards from an offline StarDict dictionary, so no network is needed for the lookup.

| Step | Where |
|------|-------|
| Build the dictionary | `py -3 scripts/build_etymology_dict.py` (produces `dictionaries/build/etymology.ifo/.idx/.dict`) |
| Install on device | Copy those three files into KOReader's `data/dict/` folder |
| Select it | **Settings → Card defaults → Vocabulary Card → Etymology dictionary** (pick the installed StarDict name, e.g. `Etymology (Wiktionary)`) |

The dictionary name must match the name in the `.ifo` file (`bookname` field). The two dictionary settings are chosen from a **picker of installed StarDicts**, so you do not have to type exact names. The **Preferred dictionary** fills the **Definition** field and the **Etymology dictionary** fills the **Etymology** field — they are looked up separately, so a card draws from two dictionaries at once. If the etymology dictionary has no entry for a word, the `Etymology` field is left empty and the plugin shows a short notice (batch sends count these as "had no etymology entry").

---

## Where cards go & deck picker shortcuts

**Card defaults → Where cards go…** (Vocabulary automatic routing):

| Item | Purpose |
|------|---------|
| **Live preview** | Shows resolved Anki deck for Vocabulary using the open book (or defaults only if no book is open) |
| **Append book title to deck name** | When ON, appends `::Book Title` to the parent segment of the base deck |
| **Book overrides…** | List, add, edit, or remove per-book deck mappings that replace the card-type default |

**Card defaults → Deck picker shortcuts…** (manual send only):

| Item | Purpose |
|------|---------|
| **Favorite decks…** | Pin decks at the top of the deck picker (★). Does not change automatic routing. |
| **Recent** | Last 5 decks you picked manually — updated automatically when you send from the card viewer |

Memorization cards use **Card defaults → Memorization Card** for deck rules; they are not affected by **Where cards go**.

**Hub menu labels:** Under **Card defaults → Vocabulary Card**, set **Hub menu label** to rename the highlight-menu entry (empty = default `Vocabulary Card`). Does not change the long-press **Create Vocab Card** dictionary button.

On device, open **Settings → View settings guide** or see **docs/in-app/settings-ui.md** for a concise settings reference.

---

## Sync and storage

| Feature | File / setting |
|---------|----------------|
| Pending card queue (outbox) | `ankikoflash_cards.json` |
| Recently sent log (on-device confirmation) | `ankikoflash_recent_sent.json` (local only) |
| Settings | `ankikoflash_settings.json` |
| Send pending when WiFi (every 20 min) | Settings → Sync |
| Cloud sync | Optional backup of pending cards to a sync server |

These filenames are migrated automatically from the older `ankikooai_*` names on first load after upgrading.

Highlight colors (KOReader): **orange** = pending in My Cards queue; **green** = confirmed in Anki (highlight kept). Vocabulary and memorization highlights are **removed** from the book after a successful send when the book is open. Background auto-send (no book open) still deletes queue rows and logs **Recently sent**, but cannot remove highlights until you reopen the same source book — AnkiKoFlash then removes matching **orange** vocab/mem highlights using the stored document identity and structural position. Legacy Recently Sent rows without a source document are deliberately skipped. Run **Tag Bank Highlight Sync → Sync now** so Obsidian `library/` matches the sidecar JSON.

**Send pending when WiFi (every 20 min):** When ON and WiFi is up, pending cards in **My Cards** are flushed to AnkiConnect silently in the background (no progress overlay). If Anki is unreachable, the plugin backs off up to an hour between attempts. Turn OFF while reading without Anki to avoid any network activity.

**My Cards batch send:** **Send pending** and **Send Selected to Anki** show a **Sending… N/M** toast while each card is sent (manual sends only). **Send pending when WiFi** background flush stays silent. Both batch actions reconcile with Anki when a note already exists (duplicate rejection) or when a send timed out but the note is found in the target deck. Confirmed cards are **deleted from the queue** and appended to **Recently sent**. If Anki accepted a note but queue deletion fails, the compatibility `sent_to_anki` marker prevents automatic duplicate sends and cleanup retries later. **Check Selected against Anki** (or **Check pending against Anki** per book) runs the same Phrase + deck lookup without sending.

Pending cards, settings, and cloud merges use atomic JSON replacement. The original file survives encode/write/replace failures. On next access, the plugin validates both the canonical file and its owned `.atomic-json.bak`; a valid backup replaces a malformed/torn canonical, and the sole valid copy is never discarded.

Cloud card identity preserves current Vocabulary phrase+book behavior. Memorization identity additionally uses normalized passage text so distinct passages survive merge. Valid local/remote snapshots use the cached baseline for true three-way change/delete conflict handling; edits are preserved when the other side deletes an unchanged baseline row. Absent, empty-file, or malformed data never causes destructive deletion. Changing cloud servers removes and verifies the old `.sync` baseline before committing the new setting.

### Retry policy

AnkiKoFlash retries transient failures for idempotent reads only (for example connection/version, deck/model lists, and note lookups), with at most three attempts. Retryable failures include connection/timeouts, HTTP 408/429, and selected 5xx responses. Authentication, bad-request, and not-found responses are not retried.

`addNote`, multi-note writes, deletion, deck creation, and other writes are never blindly retried. A successful `addNote` must return a valid numeric note ID. After an ambiguous or duplicate send, the plugin fetches candidate note details and clears the queue only when the target deck, note type, identity, and relevant fields match exactly.

### Privacy

Operational warnings are structured and privacy-safe. They record outcomes/reason codes without highlight text, card content, credentials, request/response bodies, authorization values, or credential-bearing URLs.

---

## Security checklist for GitHub

- Commit **`configuration.lua.sample`** only
- Do **not** commit `configuration.lua`, `*_settings.json`, `*_cards.json`, or logs
- When sharing logs, still review them first; the plugin redacts its structured hardening events, but other KOReader components may log independently

---

## Related guides

- [Getting started](getting-started.md)
- [Plugin & recent work summary](plugin-and-recent-work-summary.md)
- [Anki: Vocabulary Card setup](anki-vocabulary-card.md)
- [Anki: Memorization deck](anki-memorization.md)
