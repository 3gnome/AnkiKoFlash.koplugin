# Documentation

Guides for setting up Anki decks that match this plugin, configuring KOReader, and studying effectively.

## Start here

| Guide | What it covers |
|-------|----------------|
| [Getting started](getting-started.md) | Install plugin → set up Anki → first card in ~15 minutes |
| [WebDAV setup (Windows)](webdav-setup-windows.md) | Local WebDAV for [Tag Bank Highlight Sync](https://github.com/3gnome/tagbankhighlightsync.koplugin) on home Wi‑Fi |
| [Tag Bank companion](tag-bank-companion.md) | Optional tags, JSON sync, Obsidian quote library |
| [Plugin configuration](plugin-configuration.md) | Card defaults, one-tap send, AnkiConnect, memorization behavior, etymology dictionary |
| [Anki: Vocabulary Card setup](anki-vocabulary-card.md) | **Vocabulary Card** note type (dictionary + etymology), templates, CSS, deck options |
| [Anki: Memorization deck](anki-memorization.md) | **Memorization** note type, step/full cards, filtered deck, study routine |
| [Publishing & discoverability](publishing.md) | GitHub setup, descriptions, topics, releases, AppStore |
| [Plugin & recent work summary](plugin-and-recent-work-summary.md) | What AnkiKoFlash is, TagBank companion, recent dev session work |

## Copy-paste reference (use on your computer)

Open these in **Notepad, VS Code, or any text editor** on your PC and paste directly into Anki's note-type editor (Cards tab):

| File | Use for |
|------|---------|
| [docs/desktop/vocabulary-card-anki-templates.txt](desktop/vocabulary-card-anki-templates.txt) | Vocabulary Card front/back + CSS (includes Etymology) |
| [docs/desktop/memorization-anki-templates.txt](desktop/memorization-anki-templates.txt) | Memorization Line/Full templates + CSS |
| [anki-memorization-setup.txt](../anki-memorization-setup.txt) | Same as memorization desktop file (plugin root) |

**On your e-reader**, tap **View README** in each card submenu for what that card type does (fields, decks, settings). Copy templates and CSS on your computer from the desktop `.txt` files above — not from the e-reader screen. Full Markdown guides (deck options, study routine, etc.) remain in the `docs/*.md` files above.

## In-app vs desktop docs

| On device (plugin) | On computer (copy-paste) | Full formatted guide |
|--------------------|--------------------------|----------------------|
| `docs/in-app/vocabulary-card.md` | `docs/desktop/vocabulary-card-anki-templates.txt` | [anki-vocabulary-card.md](anki-vocabulary-card.md) |
| `docs/in-app/memorization.md` | `docs/desktop/memorization-anki-templates.txt` | [anki-memorization.md](anki-memorization.md) |

## Two Anki workflows

This plugin supports two separate flows:

1. **Vocabulary Card** — highlight a word → KOReader dictionary lookup + offline etymology → send to your vocabulary default deck (**Card defaults → Vocabulary Card**). Anki note type: **Vocabulary Card**. No accounts, no network beyond AnkiConnect.
2. **Memorization Card** — highlight a poem or passage → overlapping step cards + full recitation → send to `Memorize::Book::location` subdecks (**Card defaults → Memorization Card**).

Each flow needs its **own Anki note type and default deck**. Configure both under **Settings → Card defaults** (Vocabulary Card or Memorization Card). Use **Where cards go…** for subdeck-by-book and per-book overrides — not for default deck selection. Use **Deck picker shortcuts…** for favorite decks when sending manually. In Settings, **tap gray rows for help.**

## Field names must match

AnkiConnect sends data using exact field names. Renaming fields in Anki without updating the plugin will break sends.

| Menu label | Anki note type | Required fields |
|------------|----------------|-----------------|
| Vocabulary Card | Vocabulary Card | `Phrase`, `Definition`, `Etymology`, `Context`, `Source` |
| Memorization Card | Memorization | `Title`, `Context`, `Target`, `FullText`, `Source`, `LineIndex`, `FullRecite` |

The **Etymology** field is optional on the Anki side if you do not install the etymology dictionary — the plugin simply leaves it empty. For the full definition + etymology card, install the etymology dictionary and include the field.
