# Tag Bank companion (optional)

[Tag Bank Highlight Sync](https://github.com/3gnome/tagbankhighlightsync.koplugin) tags highlights, merges `*.sdr.json` across devices via cloud storage, and exports a Markdown quote library for Obsidian. **AnkiKoFlash** handles Anki flashcards — either plugin works alone.

## Division of labor

| Task | Plugin |
|------|--------|
| Vocab / Memorization cards → Anki | **AnkiKoFlash** |
| View / delete / batch-send highlights as cards | **AnkiKoFlash** |
| Tag highlights, folder hierarchy | **Tag Bank** |
| JSON device sync + Obsidian `library/` export | **Tag Bank** |

## Cross-plugin features

When both are installed:

- **View All Highlights → Sync All Highlights** — Tag Bank batch sync for all books in reading history
- Tag Bank quote-library filters use Anki-branded orange/green labels

## Install Tag Bank

1. [Releases](https://github.com/3gnome/tagbankhighlightsync.koplugin/releases) — copy `tagbankhighlightsync.koplugin` into `koreader/plugins/`
2. [Getting started](https://github.com/3gnome/tagbankhighlightsync.koplugin/blob/main/docs/getting-started.md)
3. [WebDAV setup (Windows)](webdav-setup-windows.md) — shared home Wi‑Fi sync guide

## Typical workflow

Read → tag (Tag Bank) → send cards (AnkiKoFlash) → **Sync now** (Tag Bank) → browse `library/` in Obsidian.

See also [Tag Bank — AnkiKoFlash companion](https://github.com/3gnome/tagbankhighlightsync.koplugin/blob/main/docs/companion-ankikoflash.md).
