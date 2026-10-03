# Anki: Vocabulary Card setup (dictionary + etymology, offline)

> **On your e-reader:** Tap **View README** in the Vocabulary Card submenu for a short summary (`docs/in-app/vocabulary-card.md`).  
> **Copy-paste on your computer:** Anki front/back templates and CSS are in **`docs/desktop/vocabulary-card-anki-templates.txt`** — open in any text editor and paste into Anki's note-type editor.

**Vocabulary Card** is the menu label in AnkiKoFlash. In Anki, create a note type named **Vocabulary Card** with the fields below — the plugin sends data to those exact names via AnkiConnect.

This flow uses **KOReader's installed StarDict dictionaries only** — the definition from your chosen dictionary, and the etymology from the offline etymology dictionary. No accounts, no network beyond the AnkiConnect send. Install at least one dictionary in KOReader (Search → Dictionary support in the KOReader wiki) before using this button.

## 1. Create the note type

1. Anki → **Tools → Manage Note Types → Add → Add: Basic**
2. Rename the note type to exactly: **Vocabulary Card**
3. Open **Fields** — delete `Front` and `Back`, then add fields **in this order**:

   | Order | Field name |
   |-------|------------|
   | 1 | Phrase |
   | 2 | Definition |
   | 3 | Etymology |
   | 4 | Context |
   | 5 | Source |

4. **Cards** — keep a single card type (Card 1).

## 2. Front template

Open **`docs/desktop/vocabulary-card-anki-templates.txt`** → **Part 2** and paste into **Cards → Card 1 → Front Template**.

## 3. Back template

Open **`docs/desktop/vocabulary-card-anki-templates.txt`** → **Part 3** and paste into **Cards → Card 1 → Back Template**. The template includes a small `<script>` that styles part-of-speech labels (Noun, Verb, …) and grammar/usage markers in the definition.

## 4. Styling

Open **`docs/desktop/vocabulary-card-anki-templates.txt`** → **Part 4** and paste into **Cards → Styling** (shared by front and back).

## 5. Deck

Use your vocabulary deck — default **English::Koreader**. Subdecks by book title work the same way.

Create a **Vocabulary Card** deck-options preset (or reuse another preset) with similar new/review limits.

## 6. Deck options preset

Suggested values for dictionary drill cards:

| Setting | Suggested |
|---------|-----------|
| New cards/day | 30–50 |
| Maximum reviews/day | 250 |
| Learning steps | `1m 10m 1d` |
| Graduating interval | 2 days |
| Easy interval | 4 days |
| Starting ease | 250% |
| Bury related new/siblings | OFF |

Dictionary definitions are short — slightly higher daily caps are often comfortable.

## 7. Plugin settings (must match Anki)

Configure on device under **AnkiKoFlash → Settings → Card defaults**:

| Setting | Default | Menu path |
|---------|---------|-----------|
| Vocabulary note type | Vocabulary Card | Card defaults → Vocabulary Card… |
| Default deck | English::Koreader | Card defaults → Vocabulary Card… |
| Preferred dictionary | reader.dict EN | Card defaults → Vocabulary Card… |
| Etymology dictionary | Etymology (Wiktionary) | Card defaults → Vocabulary Card… |
| One-tap send (Vocabulary) | OFF | Card defaults → Vocabulary Card… |
| Save only (skip send to Anki) | OFF | AnkiKoFlash hub menu |
| Subdeck by book title | ON | Card defaults → Where cards go… |
| Tags | KOReader | Settings → Tags… |

**One-tap send** uses your default deck and auto-picks the preferred dictionary when set. With multiple dictionaries and no preferred name, the plugin shows the picker once (the etymology dictionary is excluded from that picker).

**Save only** is a toggle in the **AnkiKoFlash hub menu** (not Settings): when ON, Vocabulary Card skips the note-type and dictionary pickers and uses the default deck, but saves locally and never attempts to reach Anki. It takes precedence over one-tap send, so cards stay in **My Cards** until you send them manually.

**Preferred dictionary** and **Etymology dictionary** are set with a **picker of installed StarDicts** (no typing exact names). The preferred dictionary fills the `Definition` field; the etymology dictionary fills the `Etymology` field. Both are looked up separately, so a single card draws from two dictionaries. Leave a field empty to skip it. If the etymology dictionary has no entry for a word, the `Etymology` field is left empty and the plugin shows a short notice (batch sends count these as "had no etymology entry").

In `configuration.lua`:

```lua
anki = {
    url   = "http://192.168.1.100:8765",
    vocabulary_deck = "English::Koreader",
    vocabulary_model = "Vocabulary Card",
    auto_send_vocabulary = false,
    save_only_vocabulary = false,
    vocabulary_preferred_dictionary = "reader.dict EN",
    etymology_preferred_dictionary = "Etymology (Wiktionary)",
    tags  = { "KOReader" },
},
```

## 8. What the plugin sends

| Field | Content |
|-------|---------|
| Phrase | Highlighted word or phrase (from dictionary headword when available) |
| Definition | Plain-text definition from your KOReader dictionary |
| Etymology | Word origin from the offline etymology dictionary |
| Context | Surrounding passage from the book (~10 lines) |
| Source | Book title, author, page/chapter (from KOReader metadata) |

## 9. KOReader dictionary requirement

1. Install StarDict dictionaries in KOReader's `data/dict/` folder.
2. Enable dictionaries in **Search → Dictionary settings**.
3. Test a normal long-press lookup, then tap **Create Vocab Card** in the dictionary popup (or use **AnkiKoFlash → Vocabulary Card** from the highlight menu).

If lookup fails, the plugin shows an error — there is no fallback for this flow.

To fill the **Etymology** field, build and install the offline etymology dictionary (see [Plugin configuration](plugin-configuration.md#etymology-dictionary)), then select it under **Card defaults → Vocabulary Card → Etymology dictionary**.

## Related

- **Memorization Card** — [anki-memorization.md](anki-memorization.md)
- **Plugin configuration** — [plugin-configuration.md](plugin-configuration.md)
