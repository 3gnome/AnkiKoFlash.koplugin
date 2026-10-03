# AnkiKoFlash

KOReader plugin: long-press a word or highlight a passage while reading → dictionary flashcards (with offline etymology) or LPCG-style memorization decks → sync to Anki via [AnkiConnect](https://foosoft.net/projects/anki-connect/).

Works on Kobo, Kindle (with KOReader), and the KOReader desktop emulator.

Unlike manually exporting highlights, AnkiKoFlash builds finished, formatted cards — a dictionary definition plus its etymology, or a set of memorization steps — and sends them straight to Anki over your Wi‑Fi. No cables, no copy‑paste, no API keys, no cloud accounts.

## Demo

From a highlight to a finished Anki card, without leaving your book:

| 1. Long-press / highlight | 2. Review the card | 3. Pick an Anki deck |
|---|---|---|
| ![Highlight menu with the AnkiKoFlash entry](docs/images/highlight-menu.png) | ![Vocabulary card preview on the device](docs/images/card-preview.png) | ![Choosing the target Anki deck](docs/images/deck-picker.png) |

The card lands in desktop Anki, ready to study:

![The finished card in desktop Anki](docs/images/anki-card.png)

### Memorization (poetry & prose)

Highlight a poem or passage and AnkiKoFlash builds LPCG-style overlapping step cards plus a full-recitation card:

| 1. Create Memorization Card | 2. Confirm the deck | 3. Step card in Anki |
|---|---|---|
| ![Memorization entry in the AnkiKoFlash menu](docs/images/memorization-menu.png) | ![Confirmation showing step + recitation cards](docs/images/memorization-confirm.png) | ![A memorization step card in Anki](docs/images/memorization-anki.png) |

<!-- Optional: add a short screen recording as docs/images/demo.gif and embed it above for social posts. -->

## Features

- **Vocabulary Card** — KOReader dictionary lookup plus an **Etymology** section from a bundled offline etymology dictionary (definition + etymology + passage + source, no network required)
- **Memorization Card** — overlapping step cards + full-recitation card for poetry and prose ([AnkiLPCG](https://ankilpcg.readthedocs.io/)-style)
- **AnkiConnect** — send to desktop Anki; optional auto-sync to AnkiWeb after send
- **My Cards** — pending outbox only; **Recently sent** log for confirmed sends; manual batch send shows **Sending… N/M** progress; batch send reconciles duplicates/timeouts and removes cards from the queue
- **View All Highlights** — checklist of highlights from the current book (or **Switch book…** for any book in history): multi-select, **Delete Selected Highlights** (open book only), batch send as Vocabulary/Memorization; **Sync All Highlights** when [Tag Bank](https://github.com/3gnome/tagbankhighlightsync.koplugin) is installed
- **Settings UI** — card defaults (note types, decks, one-tap send), memorization behavior, sync; gray rows = tap for help (no file editing on device)
- **One-tap send** — per card type: skip note-type/deck prompts and send straight to your default deck
- **Save only** — hub-menu toggle: skip prompts and save vocabulary cards locally with no network attempt (great when you're away from your Anki PC)
- **Loss-resistant queue** — atomic local/cloud writes, safe startup recovery, and non-destructive cloud merging
- **Long-workflow safeguards** — cancellable inbox batches, bounded memorization confirmation, and partial-send recovery

## Quick start

1. Install the plugin into `koreader/plugins/AnkiKoFlash.koplugin/`
2. Set up two Anki note types: **Vocabulary Card** and **Memorization**
3. Configure AnkiConnect on your PC and enter your LAN URL in plugin Settings
4. Long-press a word or highlight text → **View All Highlights**, **AnkiKoFlash**, or **Memorize** (scroll the highlight menu). **AnkiKoFlash** opens the hub for card types, **My Cards**, and settings. Or long-press → **Dictionary** → **AnkiKoFlash** or **Create Vocab Card**.

**Full walkthrough:** [docs/getting-started.md](docs/getting-started.md)

## Documentation

| Guide | Contents |
|-------|----------|
| [Documentation index](docs/README.md) | Overview of all guides |
| [Getting started](docs/getting-started.md) | Install, AnkiConnect, first card |
| [Tag Bank companion](docs/tag-bank-companion.md) | Optional tags, JSON sync, Obsidian quote library |
| [WebDAV setup (Windows)](docs/webdav-setup-windows.md) | Local WebDAV for Tag Bank on home Wi‑Fi |
| [Plugin & recent work summary](docs/plugin-and-recent-work-summary.md) | Architecture, TagBank companion, dev session notes |
| [Plugin configuration](docs/plugin-configuration.md) | Settings UI, `configuration.lua` |
| [Anki: Vocabulary Card setup](docs/anki-vocabulary-card.md) | Dictionary-only note type (with etymology) |
| [Anki: Memorization deck](docs/anki-memorization.md) | Step/full cards, deck hierarchy, weekly routine |
| [Desktop copy-paste templates](docs/desktop/) | Front/back HTML + CSS for both note types |
| [anki-memorization-setup.txt](anki-memorization-setup.txt) | Memorization templates (same as `docs/desktop/memorization-anki-templates.txt`) |
| [Publishing & discoverability](docs/publishing.md) | GitHub, releases, KOReader AppStore, SEO |
| [Announcement posts](docs/announcements.md) | Ready-to-paste posts for MobileRead, Reddit, Anki forums |

On your e-reader, tap **View README** in each card submenu for what that card type does (fields, decks, settings). Copy Anki templates and CSS on your computer from [docs/desktop/](docs/desktop/) — not from the e-reader screen.

## Requirements

| Component | Purpose |
|-----------|---------|
| [KOReader](https://koreader.rocks/) | E-reader app |
| [Anki](https://apps.ankiweb.net/) + [AnkiConnect](https://foosoft.net/projects/anki-connect/) | Desktop on same Wi‑Fi as your device |
| StarDict dictionaries | For **Vocabulary Card** lookups — install in KOReader |
| Etymology dictionary (StarDict) | Optional but recommended — fills the **Etymology** field offline |
| Anki note types | **Vocabulary Card** and **Memorization** — see docs above |

## Vocabulary Card

A **Vocabulary Card** is a dictionary drill card built entirely from KOReader's installed dictionaries — no network, no accounts. Highlight a word while reading and AnkiKoFlash will:

1. Look up the word in your KOReader StarDict dictionary
2. Look up its **etymology** in the offline etymology dictionary (when installed)
3. Add the **surrounding passage** from your book
4. Send `Phrase`, `Definition`, `Etymology`, `Context`, and `Source` to Anki

On study, the **term** is on the front; the **definition, etymology, and passage** are on the back.

### Etymology dictionary

AnkiKoFlash ships with a build script (`scripts/build_etymology_dict.py`) that produces a compact, offline StarDict dictionary from the Wiktionary English snapshot. Install the resulting `etymology.ifo/.idx/.dict` into KOReader's `data/dict/` folder (same place as your other dictionaries), then set **Settings → Card defaults → Vocabulary Card → Etymology dictionary** to its name (e.g. `Etymology (Wiktionary)`).

- The dictionary is **offline** — etymology is looked up on-device, never over the network.
- If the etymology dictionary is missing, the card is still built from the definition and passage alone; the `Etymology` field is simply left empty.

### Set up Anki first (required)

Create an Anki note type named **Vocabulary Card** with these **exact field names** (order matters for templates):

| Field | Purpose |
|-------|---------|
| Phrase | Highlighted term (front) |
| Definition | Dictionary definition (back) |
| Etymology | Word origin, from the offline etymology dictionary (back) |
| Context | Surrounding passage from your book |
| Source | Book title, author, page (filled by plugin) |

Copy-paste **front/back templates, CSS, and deck study settings**:

→ **[docs/anki-vocabulary-card.md](docs/anki-vocabulary-card.md)** (Vocabulary Card setup guide)

Default deck: `English::Koreader`. Configure note type and **One-tap send (Vocabulary)** under **Settings → Card defaults → Vocabulary Card**.

## Memorization Card

For poetry and prose memorization, highlight a passage and AnkiKoFlash builds overlapping step cards plus an optional full-recitation card:

→ **[docs/anki-memorization.md](docs/anki-memorization.md)** (full setup guide)

## Installation

1. Copy this folder to your device:

   ```
   koreader/plugins/AnkiKoFlash.koplugin/
   ```

   (Folder name must end in `.koplugin`.)

2. Create local config from the sample (optional if you use Settings on device):

   ```bash
   cp configuration.lua.sample configuration.lua
   ```

   Edit `configuration.lua` with your AnkiConnect URL, **or** enter it in **AnkiKoFlash → Settings** on the device (recommended on Kobo).

3. On the PC running Anki:
   - Install AnkiConnect (Tools → Add-ons → `2055492159`)
   - Use your PC's **LAN IP** in the plugin, not `localhost`

4. Restart KOReader.

## Anki setup (required)

The plugin sends notes via AnkiConnect — field names and note types must exist in Anki first.

| Workflow | Plugin menu | Anki note type | Default deck | Setup guide |
|----------|-------------|----------------|--------------|-------------|
| Vocabulary Card | Vocabulary Card | Vocabulary Card | `English::Koreader` | [anki-vocabulary-card.md](docs/anki-vocabulary-card.md) |
| Memorization | Memorization Card | Memorization | `Memorize` (+ subdecks) | [anki-memorization.md](docs/anki-memorization.md) |

Create deck-options presets in Anki:

- **Vocabulary Card** — for dictionary drill cards
- **Memorize** — for step/full cards (lower new-card cap, verbatim tuning)

## Configuration

| Setting | Where |
|---------|--------|
| AnkiConnect URL | **Settings → Anki connection…** or `configuration.lua` → `anki.url` |
| Vocabulary / Memorization note types | **Settings → Card defaults…** (per card type) |
| Default deck (Vocabulary) | **Settings → Card defaults → Vocabulary Card…** |
| Hub menu label (Vocabulary) | **Settings → Card defaults → Vocabulary Card…** (empty = default hub text) |
| Memorization parent deck | **Settings → Card defaults → Memorization Card…** |
| Subdeck by book (Vocabulary) | **Settings → Card defaults → Where cards go…** |
| Preferred dictionary | **Settings → Card defaults → Vocabulary Card…** |
| Etymology dictionary | **Settings → Card defaults → Vocabulary Card…** |
| One-tap send (per card type) | **Settings → Card defaults…** |
| Save only (skip send to Anki) | **AnkiKoFlash hub menu** (toggle) |
| Memorization split/context behavior | **Settings → Memorization options…** |
| Confirm before very large memorization sends | **Settings → Memorization options → Max memorization steps** (default 80) |
| Sync to AnkiWeb after send | **Settings → Anki connection…** (default ON) |
| Send pending when WiFi (every 20 min) | **Settings → Sync…** |

Details: [docs/plugin-configuration.md](docs/plugin-configuration.md). In Settings on device, **tap gray rows for help.**

`configuration.lua` is **gitignored** — never commit LAN URLs or local settings.

### Reliability and recovery

- Pending cards and settings are written atomically. An interrupted replacement may leave an owned `.atomic-json.bak`; the plugin restores it on the next access when the canonical file is missing.
- AnkiConnect automatically retries only transient, idempotent reads. It never blindly retries note creation or other writes. After an ambiguous send, it verifies the note in Anki before clearing the queue.
- Memorization notes are sent in batches of at most 50. Passages above **Max memorization steps** require confirmation and are never silently truncated.
- If only part of a memorization passage is confirmed in Anki, the original passage remains pending so it can be retried safely.
- Failed settings writes are reported and the in-memory edit is rolled back. Logs omit highlight text, credentials, request bodies, and credential-bearing URLs.

## Development (WSL emulator)

```bash
# AnkiKoFlash + TagBankHighlightSync: sync both, launch once (recommended)
bash dev-start.sh --emulator alice.epub

# One-time WebDAV + cloud plugin setup (TagBankHighlightSync repo):
# bash /path/to/tagbankhighlightsync.koplugin/setup-emulator-cloud.sh
# bash /path/to/tagbankhighlightsync.koplugin/configure-emulator-webdav.sh

# Sync without launching (then launch once manually or via dev-start.sh without --sync-only)
bash dev-start.sh --sync-only

# AnkiKoFlash only
bash start.sh --emulator alice.epub
bash start.sh --sync-only
```

Run the complete local validation suite with:

```bash
bash _check.sh
```

The suite owns and removes only its temporary test directories; do not use broad `git clean` as test cleanup.

Set `KOREADER_DIR` if your emulator is not at `~/koreader-dev/emulator/usr/lib/koreader`.

On WSL, avoid two full emulator launches per session — a second launch often triggers WSLg
`[WARN: COPY MODE]` in the taskbar (not in terminal logs). AppImage from WSL still uses WSLg.

For Cursor context: copy `LOCAL_DEV.md.sample` → `LOCAL_DEV.md` (gitignored) and edit paths for your machine. Attach `@LOCAL_DEV.md` in chat anytime.

## About this plugin

**AnkiKoFlash** connects reading on KOReader to spaced repetition in Anki. Highlight text → **View All Highlights** (browse/delete/batch), **AnkiKoFlash** hub → **Vocabulary Card**, **Memorization Card**, **My Cards**, batch highlights, or settings.

## Publishing / cloning safely

- Commit **`configuration.lua.sample`** only (placeholders).
- Do **not** commit `configuration.lua`, `*.json` card/settings files, or `koreader.log`.

**Publishing to GitHub:** [docs/publishing.md](docs/publishing.md) — repo setup, release zip, GitHub topics (`koreader-plugin` for AppStore), and discoverability.

## License

MIT — see [LICENSE](LICENSE).

## Credits

- Memorization flow inspired by [AnkiLPCG](https://ankilpcg.readthedocs.io/)
- Anki integration via [AnkiConnect](https://foosoft.net/projects/anki-connect/)
- Etymology dictionary derived from the Wiktionary English StarDict snapshot (CC BY-SA)
