# Anki: Memorization deck

> **On your e-reader:** Tap **View README** in the Memorization submenu for a short summary (`docs/in-app/memorization.md`).  
> **Copy-paste on your computer:** Line/Full templates and CSS are in **`docs/desktop/memorization-anki-templates.txt`** (same as `anki-memorization-setup.txt` at the plugin root) — open in any text editor and paste into Anki’s note-type editor.

LPCG-style verbatim memorization: overlapping **step** cards (recite the next line/chunk) plus an optional **full recitation** card per passage.

Highlight menu action: **Memorization**

Note type name must be exactly: **Memorization**

---

## 1. Create the note type

1. **Tools → Manage Note Types → Add → Add: Basic**
2. Rename to: **Memorization**
3. **Fields** — delete Front/Back, add in order:

   | Field | Purpose |
   |-------|---------|
   | Title | Passage title (book + location) |
   | Context | Prior lines shown as cue |
   | Target | Line/chunk to recite |
   | FullText | Complete passage (full card back) |
   | Source | Book citation |
   | LineIndex | Step number (plugin-managed) |
   | FullRecite | Non-empty on full-recitation notes only |

4. **Cards** — create **two** card types:

   | Card type | Purpose |
   |-----------|---------|
   | **Line** | Daily step cards (tag `memorization::step`) |
   | **Full** | Weekly whole-passage recitation (tag `memorization::full`) |

---

## 2. Line card — front template

Open **`docs/desktop/memorization-anki-templates.txt`** → **PART 2** and paste into **Cards → Line → Front Template**.

## 3. Line card — back template

Open **`docs/desktop/memorization-anki-templates.txt`** → **PART 3** and paste into **Cards → Line → Back Template**. Remove the `{{type:Target}}` line if you do not want typing checks.

## 4. Full card — front template

Open **`docs/desktop/memorization-anki-templates.txt`** → **PART 4** and paste into **Cards → Full → Front Template**.

## 5. Full card — back template

Open **`docs/desktop/memorization-anki-templates.txt`** → **PART 5** and paste into **Cards → Full → Back Template**.

## 6. Styling

Open **`docs/desktop/memorization-anki-templates.txt`** → **PART 6** and paste into **Cards → Styling** (both card types share this).

---

## 7. Deck hierarchy

1. Create parent deck: **Memorize**
2. The plugin auto-creates subdecks per highlight:

   ```
   Memorize::Alice's Adventures in Wonderland::p. 16
   ```

   Book title is the middle level; the leaf is page/chapter only (not repeated).

3. In plugin **Settings → Card defaults → Memorization Card**, set **Parent deck** to `Memorize`.

---

## 8. Deck options (Memorize preset)

**Decks → ⚙ → Options → Save as preset → "Memorize"**

Apply to **Memorize** and use **Save to all subdecks** when you add new passages.

### Quick reference

| Setting | Value |
|---------|-------|
| New cards/day | 10 |
| Maximum reviews/day | 100 |
| Learning steps (FSRS on) | `1m 10m` |
| Learning steps (FSRS off) | `1m 10m 1d` |
| Relearning steps (FSRS on) | `10m` |
| Relearning steps (FSRS off) | `10m 1d` |
| New card gather order | Deck order |
| New card sort order | Order gathered |
| Review sort order | Due date, then random |
| Bury interday learning siblings | On |
| Bury review siblings | Off |
| Leech threshold | 8 |
| Leech action | Tag only |
| FSRS desired retention | 90% |

### Key ideas

- **10 new/day** — a 10-step passage ≈ 11 cards with full card; prevents overload.
- **100 reviews/day** — verbatim recitation takes longer than vocab.
- **No `1d` learning step with FSRS** — FSRS schedules long intervals; same-day steps only.
- **Review sort random** — do not force strict 1→2→3 order; fluency comes from aloud practice, not queue order.

For a field-by-field explanation of every deck option, see [anki-memorization-setup.txt](../anki-memorization-setup.txt) Part 7.

---

## 9. Filtered deck (weekly full recitation)

Step cards belong in daily study. Full cards (`memorization::full`) work best 1–2× per week.

### Create once

1. **Tools → Create Deck** → name: `Memorize :: Full recitation (weekly)`
2. Open the deck → **Options** (gear)
3. Set filter: **Show only cards with tag** `memorization::full`
4. Optional limits: 20 new/day, 50 reviews/day

### Weekly routine

| When | What |
|------|------|
| Mon–Sat | Study the passage subdeck (step cards) |
| 1–2×/week | Study **Memorize :: Full recitation (weekly)** — recite aloud, grade honestly |

Browse search: `tag:memorization::full`

---

## 10. Plugin settings (Memorization)

Settings are split between **Card defaults** (where cards go) and **Memorization options** (how text is split).

### Card defaults → Memorization Card

| Setting | Default | Notes |
|---------|---------|-------|
| Note type | Memorization | Must match Anki |
| Parent deck | Memorize | Top-level deck; subdecks auto-created |
| One-tap send (Memorization) | OFF | Skip intro/confirm; send immediately |
| Quick highlight button | OFF | “Memorize” on highlight menu (skips hub) |
| Skip hub submenu when auto-send | OFF | One tap on Memorization in hub when one-tap send is ON |

### Memorization options (behavior)

| Setting | Default | Tuning |
|---------|---------|--------|
| Context lines | 3 | 4 for poetry; 2–20 available |
| Cumulative context | OFF | ON = show all prior lines on each step |
| Max words per chunk | 7 | 6–8 for prose paragraphs |
| Full recitation card | ON | OFF to skip full card |
| Force verse line split | OFF | One step per line |
| Show step preview on send | OFF | List chunks before send |
| Replace existing cards | OFF | Delete notes in target deck first |
| Merge batch highlights | OFF | Combine inbox selections into one passage |
| Auto-save if send fails | OFF | Queue locally when one-tap send cannot reach Anki |

**How text is split:**

- **Poetry** (≥2 line breaks in selection): one unit per line; long lines split by word count.
- **Prose**: split by sentences, then by word chunks if sentences are long.

Duplicate warning: if the same book + page deck already has cards, the plugin warns before sending again (unless replace-existing is ON).

`configuration.lua` → `memorize` section (behavior defaults; deck/note type also in `anki` / Card defaults):

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
    tags                    = { "KOReader", "memorization" },
},
```

On-device keys for Card defaults: `vocabulary_deck`, `memorize_parent_deck`, `memorize_model`, `auto_send_memorization`, `memorize_quick_highlight_button`, `auto_send_skip_hub_submenu`. Where cards go: `subdeck_by_book`, `per_book_decks`. Deck picker shortcuts: `favorite_decks`, `recent_decks`.

Tags added automatically:

- `memorization::step` — each chunk/line card
- `memorization::full` — whole passage card

---

## 11. Study routine (most effective)

**Before Anki (day 1):**

1. Read the passage once
2. Chain aloud: line 1 → lines 1–2 → … up to ~6 lines
3. Sleep
4. Full recitation aloud; fix weak spots only

**Daily (Anki):**

1. Review step cards in the passage subdeck
2. End with **one** full recitation aloud without looking
3. Grade the Full card based on that run-through

Inspired by [AnkiLPCG](https://ankilpcg.readthedocs.io/).

---

## Copy-paste reference

All templates and extended deck-option notes in one file:

- **`docs/desktop/memorization-anki-templates.txt`** (also **`anki-memorization-setup.txt`** at plugin root)

Vocabulary Card templates:

- **`docs/desktop/vocabulary-card-anki-templates.txt`**

Formatted guide: [Vocabulary Card](anki-vocabulary-card.md)
