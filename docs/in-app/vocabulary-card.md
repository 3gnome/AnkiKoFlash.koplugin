# Vocabulary Card — reading summary (on device)

**Vocabulary Card** uses KOReader StarDict dictionaries only — definition plus offline etymology, no accounts, no network beyond the AnkiConnect send.

Anki note type name: **Vocabulary Card**

Install at least one dictionary in KOReader before using this flow. To fill the **Etymology** field, also install the offline etymology dictionary and select it in Settings.

## How to create a card

- **Long-press** a word → dictionary popup → **Create Vocab Card** (same Card defaults as the highlight menu).
- **Highlight** text → **AnkiKoFlash → Vocabulary Card**.

## Fields (exact names)

| Order | Field |
|-------|-------|
| 1 | Phrase |
| 2 | Definition |
| 3 | Etymology |
| 4 | Context |
| 5 | Source |

## Deck

Set under **Card defaults → Vocabulary Card → Default deck** (pick from Anki). **Where cards go… → Append book title to deck name** works the same way.

## Plugin settings

Configure under **AnkiKoFlash → Settings → Card defaults → Vocabulary Card**:

- **Note type** — pick from Anki (default: Vocabulary Card)
- **Default deck** — pick from Anki
- **Preferred dictionary** — pick from your installed StarDicts (fills **Definition**); leave as (auto) to pick each time
- **Etymology dictionary** — pick from your installed StarDicts (fills **Etymology**); leave empty to skip
- **One-tap send (Vocabulary)** — skip prompts and send to your default deck
- **Save only (skip send to Anki)** — hub menu toggle: skip prompts and save locally without a network attempt

The definition and etymology come from two different dictionaries, chosen once in these settings. If the etymology dictionary has no entry for a word, **Etymology** is left empty and the plugin shows a short notice.

## Templates and CSS

Templates and CSS are not shown on device. On your computer, open **docs/desktop/vocabulary-card-anki-templates.txt** in a text editor. Copy each labeled block into Anki → Tools → Manage Note Types → Vocabulary Card → Cards.

Full guide: **docs/anki-vocabulary-card.md**
