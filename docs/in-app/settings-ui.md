# Settings — on-device help

Open from **AnkiKoFlash → Settings**. Gray rows are informational — **tap any for details**. The menu subtitle reminds you: *Tap gray rows for help.*

For the full reference on your computer, see **docs/plugin-configuration.md**.

## Main Settings

| Submenu | Purpose |
|---------|---------|
| **Card defaults…** | Note types, default decks, one-tap send, **Where cards go**, **Deck picker shortcuts** |
| **Anki connection…** | AnkiConnect URL, sync after send, test connection |
| **Tags…** | Enable tags and edit the tag list sent with cards |
| **Memorization options…** | Split/context/batch behavior (not deck routing) |
| **Sync…** | Background send when WiFi is on (every 20 min), cloud backup |

## View All Highlights

Open from the **highlight menu** or **AnkiKoFlash hub** (not under Settings).

- **Switch book…** — highlights from any book in reading history
- **Sync All Highlights** — when [Tag Bank](https://github.com/3gnome/tagbankhighlightsync.koplugin) is installed
- Select rows, **Delete Selected Highlights** (open book only), or batch-send as Vocabulary / Memorization

Same checklist as **Highlights and Cards → Highlights to Anki**.

Tap **View settings guide** on the main screen to reopen this document.

## Card defaults — hub menu labels

Under **Card defaults → Vocabulary Card**, **Hub menu label** renames the entry in the AnkiKoFlash highlight hub and in Highlights batch mode. Leave empty for the built-in default (`Vocabulary Card`).

This does **not** change the long-press **Create Vocab Card** button in the dictionary popup.

Vocabulary/Memorization hub submenus include **← Back** to return to the AnkiKoFlash hub.

## Save only (hub menu)

The **AnkiKoFlash hub menu** has a **Save only** toggle (not in Settings). When ON, Vocabulary Card skips the note-type and dictionary pickers and uses the default deck, but saves locally and never attempts to reach Anki. It takes precedence over one-tap send — cards wait in **My Cards** until you send them manually.

## Where cards go (Vocabulary)

Automatic deck routing when cards are saved or sent:

1. Card-type default deck (**Vocabulary Card**)
2. **Book override** for matching `book_title`, if set
3. **Append book title to deck name** — when ON, adds `::Book Title` to the parent deck segment

Gray preview rows show the resolved deck for the open book. **Memorization** uses **Card defaults → Memorization Card** instead — not this screen.

## Deck picker shortcuts

**Favorite decks** and **Recent** decks appear at the top when you **manually choose a deck** at send time. They do not change automatic routing or one-tap send.

Recent decks (last 5) are saved automatically when you send from the card viewer.

Settings are adopted only after they are saved to device storage. If a write fails, AnkiKoFlash shows an error and keeps the previously saved value.

## Tags

When **Tags on new cards** is OFF, no tags are sent to Anki. When ON, the comma-separated tag list is applied on every AnkiConnect send (default: `KOReader`).

## Etymology dictionary

Under **Card defaults → Vocabulary Card → Etymology dictionary**, set the StarDict name used to fill the **Etymology** field (e.g. `Etymology (Wiktionary)`). The lookup is offline. Leave empty to skip etymology (or to fall back to the `Etymology` section of your general dictionary when present).

## Long memorization passages

**Memorization options → Max memorization steps** defaults to 80. It controls when AnkiKoFlash asks for confirmation; it does not truncate the passage. Notes are sent in groups of at most 50, and a partially confirmed passage remains in **My Cards** for safe retry.

## Sending and recovery

Transient connection failures are retried only for read-only AnkiConnect requests. Note creation is never blindly repeated; after a timeout, AnkiKoFlash verifies the note before removing it from the queue. If storage cannot be updated, the card remains protected from automatic duplicate sends and cleanup retries later.
