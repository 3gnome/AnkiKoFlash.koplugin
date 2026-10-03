## What's new in v1.0.9

### View All Highlights
- New entry on the **highlight menu** and **AnkiKoFlash hub → View All Highlights**
- Checklist of every highlight in the current book: multi-select, **Delete Selected Highlights**, or batch send (Vocabulary / Memorization)
- Same screen as **Highlights and Cards → Highlights to Anki**, with a clearer title when opened from the menu

### Highlight cleanup
- After background Anki send, orphan **orange** vocabulary/memorization highlights are removed on next plugin load (uses **Recently sent** positions)

### Dev tooling
- `dev-start.sh` / `dev-lib.sh` — sync AnkiKoFlash (+ optional TagBank) and launch emulator in one command
- `scripts/reset_alice.sh` — PC-only Alice test-book reset (Anki, WebDAV, Obsidian); requires TagBank regen script
- `spec/highlight_cleanup_spec.lua` — unit tests for cleanup logic
- `docs/plugin-and-recent-work-summary.md` — architecture and session notes

### Docs
- README, getting started, plugin configuration, and in-app settings help updated for View All Highlights and highlight cleanup

## Install

Download `AnkiKoFlash-v1.0.9.zip`, unzip, and copy the `AnkiKoFlash.koplugin` folder into your KOReader `plugins/` directory.

See [Getting started](https://github.com/3gnome/AnkiKoFlash.koplugin/blob/main/docs/getting-started.md) for setup.
