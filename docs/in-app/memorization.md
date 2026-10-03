# Memorization Card — reading summary (on device)

LPCG-style verbatim memorization: overlapping **step** cards plus an optional **full recitation** card per passage.

Anki note type name: **Memorization**

## Fields (exact names)

Title, Context, Target, FullText, Source, LineIndex, FullRecite

## Card types in Anki

| Card type | Purpose |
|-----------|---------|
| **Line** | Daily step cards (`memorization::step`) |
| **Full** | Whole-passage recitation (`memorization::full`) |

## Deck hierarchy

Parent deck: **Memorize** → plugin creates `Memorize::Book title::page`.

Set **Parent deck** under **Settings → Card defaults → Memorization Card** (pick from Anki).

Memorization subdecks (`Memorize::Book::page`) are created automatically; that is separate from **Where cards go…** (used for Vocabulary subdeck-by-book).

## Plugin settings

### Card defaults (note type, deck, one-tap send)

- **Note type** — default: Memorization (pick from Anki)
- **Parent deck** — default: Memorize (pick from Anki)
- **One-tap send (Memorization)** — skip intro and confirmation; send immediately
- **Quick highlight button** — add “Memorize” on the highlight menu (skips AnkiKoFlash hub)
- **Skip hub submenu when auto-send** — one tap on Memorization Card in the hub when one-tap send is ON

### Memorization options (behavior)

- Context lines: 3 (up to 20; rolling window when cumulative is OFF)
- Cumulative context: OFF (ON = show all prior lines on each step)
- Max words per chunk: 7
- Max memorization steps before confirmation: 80
- Full recitation card: ON

Optional (OFF by default):

- Force verse line split — one step per line even without auto-detect
- Show step preview on send — list each chunk before sending
- Replace existing cards — delete notes in the target deck before send
- Merge batch highlights — combine multiple inbox selections into one passage
- Auto-save if send fails — queue locally when one-tap send cannot reach Anki

The step threshold is not a truncation limit. Larger passages require confirmation, then all generated notes are sent in groups of at most 50. If only some notes are sent or verified, the passage remains pending in **My Cards** and can be retried.

## Templates and CSS

Templates and CSS are not shown on device. On your computer, open **docs/desktop/memorization-anki-templates.txt** in a text editor. Copy each labeled block into Anki → Tools → Manage Note Types → Memorization → Cards.

Full guide: **docs/anki-memorization.md**
