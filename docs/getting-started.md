# Getting started

End-to-end setup: plugin on your e-reader, Anki on your PC, first vocabulary card and (optionally) first memorization deck.

## What you need

- A device running [KOReader](https://koreader.rocks/) (Kobo, Kindle with KOReader, or the desktop emulator)
- A PC on the **same Wi‑Fi network** running [Anki](https://apps.ankiweb.net/) with the [AnkiConnect](https://foosoft.net/projects/anki-connect/) add-on (code `2055492159`)
- StarDict dictionaries installed in KOReader (for **Vocabulary Card**)
- (Optional) the offline **etymology** dictionary — fills the `Etymology` field on vocabulary cards

## Step 1 — Install the plugin

Copy this repository into KOReader's plugins folder:

```
koreader/plugins/AnkiKoFlash.koplugin/
```

The folder name **must** end in `.koplugin`.

Restart KOReader. After you select text (long-press or drag), scroll the highlight menu for **View All Highlights**, **Memorize**, and **AnkiKoFlash** (near the bottom when many plugins are installed). You can also long-press a word → **Dictionary** → **AnkiKoFlash** or **Create Vocab Card** (same row).

## Step 2 — Set up Anki (one-time)

Create **two note types** and **deck-option presets**. Skipping this step is the most common reason sends fail.

| Flow | Guide | Default deck |
|------|-------|--------------|
| Vocabulary Card | [Anki: Vocabulary Card setup](anki-vocabulary-card.md) | Configure under **Card defaults → Vocabulary Card** |
| Memorization | [Anki: Memorization deck](anki-memorization.md) | **Memorize** parent deck under **Card defaults → Memorization Card** |

Minimum checklist:

- [ ] Note type **Vocabulary Card** with fields `Phrase`, `Definition`, `Etymology`, `Context`, `Source` — see [anki-vocabulary-card.md](anki-vocabulary-card.md)
- [ ] Note type **Memorization** with card types **Line** and **Full**
- [ ] Deck for Vocabulary Card (e.g. **English::Koreader**)
- [ ] Deck **Memorize** (parent for memorization subdecks)
- [ ] Deck-options preset **Vocabulary Card** applied to the vocab deck
- [ ] Deck-options preset **Memorize** applied to `Memorize` and subdecks
- [ ] (Recommended) Filtered deck **Memorize :: Full recitation (weekly)** for full-passage cards

## Step 3 — Configure the plugin

On the device (recommended on Kobo):

1. Open **AnkiKoFlash → Settings** (or tap Settings from the AnkiKoFlash hub menu). Gray rows are informational — **tap gray rows for help.**
2. Open **Anki connection…** → set **AnkiConnect URL** to `http://YOUR_PC_LAN_IP:8765` (your PC's Wi‑Fi address, **not** `localhost`) → **Test Connection** (Anki must be running).
3. Open **Card defaults…**:
   - **Vocabulary Card…** → note type **Vocabulary Card**, default deck (e.g. `English::Koreader`), and (optionally) **Etymology dictionary** name
   - **Memorization Card…** → parent deck **Memorize**, note type **Memorization**
   - **Where cards go…** → leave **Append book title to deck name** ON if you want `Deck::Book Title`

Alternatively, copy `configuration.lua.sample` to `configuration.lua` on a PC and edit there before syncing the plugin folder to the device. On-device settings **override** the file after you save them once.

See [Plugin configuration](plugin-configuration.md) for every setting.

### Optional: one-tap send (fastest workflow)

After defaults are set, turn on **One-tap send** per card type under **Card defaults**:

| Card type | Effect |
|-----------|--------|
| Vocabulary Card | Skip note-type picker; use preferred dictionary when set; send to default deck |
| Memorization Card | Skip intro and confirmation; send step cards immediately |

Enable **Skip hub submenu when auto-send** (under **Memorization Card defaults**) to go from the AnkiKoFlash hub to the card action in one tap when one-tap send is ON.

### Save only (one-click save without Anki)

When you are away from your Anki PC, toggle **Save only** in the **AnkiKoFlash hub menu**. Vocabulary Card then skips the note-type and dictionary pickers and uses the default deck, but saves locally and never attempts to reach Anki — cards wait in **My Cards** until you send them manually.

## Step 4 — AnkiConnect on the PC

1. Anki → Tools → Add-ons → Get Add-ons → enter `2055492159`.
2. Restart Anki.
3. Find your PC's LAN IP (e.g. `ipconfig` on Windows, `ip addr` on Linux).
4. Confirm AnkiConnect listens on port **8765** (default).

Firewall must allow inbound connections on that port from your e-reader's subnet.

## Step 5 — Your first Vocabulary Card

1. Ensure KOReader dictionaries are installed and enabled.
2. **Long-press** a word → dictionary popup → **Create Vocab Card**
   *or* highlight text → **AnkiKoFlash → Vocabulary Card**.
3. If multiple dictionaries match and no preferred dictionary is set, pick an entry once.
4. Review (or auto-send) and confirm in Anki.

The `Etymology` field is filled automatically when the etymology dictionary is installed and selected — it is looked up on-device, so no network is needed beyond the AnkiConnect send.

**Tip:** Turn off **Settings → Sync → Send pending when WiFi (every 20 min)** while reading without Anki open — cards stay in **My Cards** until you send manually.

## Step 6 — Your first memorization deck (optional)

1. Highlight a short poem or paragraph (use line breaks for poetry).
2. Choose **Memorization Card** from the highlight menu.
3. If one-tap send is OFF: confirm chunk size and deck, then send.
4. If one-tap send is ON: step cards (+ optional full card) are sent immediately.

See [Anki: Memorization deck](anki-memorization.md) for study routine and filtered-deck setup.

Long passages are never silently shortened. The plugin sends generated notes in chunks of at most 50 and asks for confirmation when a passage exceeds **Settings → Memorization options → Max memorization steps** (default 80). If Anki accepts only part of a passage, the passage stays in **My Cards** and the result reports how many notes were confirmed and how many remain.

## Optional — Tag Bank & quote library

For tagging highlights, syncing JSON across devices, and exporting an Obsidian quote library, install **[Tag Bank Highlight Sync](https://github.com/3gnome/tagbankhighlightsync.koplugin)** alongside AnkiKoFlash.

| Guide | Purpose |
|-------|---------|
| [Tag Bank companion](tag-bank-companion.md) | How the two plugins work together |
| [WebDAV setup (Windows)](webdav-setup-windows.md) | Local WebDAV server on your PC |
| [Tag Bank getting started](https://github.com/3gnome/tagbankhighlightsync.koplugin/blob/main/docs/getting-started.md) | Install Tag Bank, cloud folder, first sync |

With both plugins: **View All Highlights → Sync All Highlights** syncs every book in reading history to cloud.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Cannot reach Anki" | Anki running? Correct LAN IP? Firewall? |
| Send fails / missing fields | Note type and field names must match docs exactly |
| Etymology field is empty | Install the etymology dictionary in KOReader and set **Card defaults → Vocabulary Card → Etymology dictionary** to its name |
| Dictionary lookup fails | Install/enable StarDict dictionaries in KOReader |
| Card sent to wrong deck | Check the card type's default deck under **Card defaults**; one-tap send uses that deck, not your last manual pick |
| No **AnkiKoFlash** in menu | Restart KOReader; confirm `.koplugin` folder name; plugin enabled under Tools → Plugin management. Scroll the highlight menu for **AnkiKoFlash** / **View All Highlights**. Alternative: long-press → **Dictionary** → **AnkiKoFlash** or **Create Vocab Card** |
| A send timed out | Do not immediately resend manually. AnkiKoFlash checks Anki after ambiguous sends and keeps the card pending unless the note is confirmed |
| Memorization was partly sent | Keep Anki running and retry the pending passage. The queue is cleared only after every generated note is sent or verified |
| A setting says it could not save | Check free space/write access and retry. The unsaved edit is rolled back instead of being reported as saved |

## Next steps

- **View all highlights:** highlight menu → **View All Highlights** — **Switch book…**, **Sync All Highlights** (with Tag Bank), delete (open book), batch send
- Batch highlights (same screen via manage menu): **AnkiKoFlash → Highlights and Cards → Highlights to Anki**
- Edit pending cards: **My Cards**
  - **My Cards** holds only cards waiting to send (outbox). Confirmed sends are removed from the queue and logged under **Recently sent**.
  - **Send pending to Anki** at the top, or open a book → **Send Selected to Anki** — while sending, a toast shows **Sending… N/M** (menus may close first, e.g. from the hub); a summary appears when done
  - **Check pending against Anki** (book header) or **Check Selected against Anki** — read-only lookup by **Phrase** in the target deck; found cards are removed from the queue and logged to **Recently sent** (no new Anki notes)
  - **Remove from queue** — delete pending rows without touching Anki; vocabulary/memorization highlights are removed when the book is open
  - **Long-press** a row → **Send to Anki** (one card); tap a row → card viewer → Send
  - Batch send treats Anki duplicate errors and post-timeout matches as **already in Anki**, removes them from My Cards, and logs to **Recently sent**
  - **Highlight colors:** orange = pending in queue; green = sent to Anki — tap green highlights for a brief "see Recently sent" message, not the card viewer
- Tune memorization split/context: **AnkiKoFlash → Settings → Memorization options…**
- Tune per-type decks, note types, and one-tap send: **AnkiKoFlash → Settings → Card defaults…**
- Deck routing (subdeck by book): **Card defaults → Where cards go…**
- Favorite decks (manual send): **Card defaults → Deck picker shortcuts…**
