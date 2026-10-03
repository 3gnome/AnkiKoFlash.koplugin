# Publishing to GitHub and getting found

How to publish this plugin, what to write in GitHub's About section, and how people discover KOReader plugins on the web.

---

## Plugin description (copy-paste)

Use these in GitHub, releases, forum posts, and the KOReader AppStore listing.

### One line (GitHub About — max ~350 characters)

```
KOReader plugin: long-press a word or highlight a passage → dictionary vocabulary cards (with offline etymology) or LPCG-style memorization cards → sync to Anki via AnkiConnect. Kobo, Kindle, emulator.
```

### Short (social, AppStore, issue templates)

```
AnkiKoFlash turns KOReader highlights into Anki flashcards. Build dictionary vocabulary cards with an offline etymology field, or verbatim memorization decks for poetry and prose. Sends to desktop Anki over Wi‑Fi using AnkiConnect. Works on Kobo, Kindle with KOReader, and the desktop emulator.
```

### Full (README intro, release notes, forum posts)

**AnkiKoFlash** is a KOReader plugin for readers who use [Anki](https://apps.ankiweb.net/) for spaced repetition.

While reading on an e-reader, highlight a word, phrase, or passage and choose:

- **AnkiKoFlash** — builds a *Vocabulary Card* from your KOReader dictionary (term on front; definition, etymology, and passage on back) and sends it to your Anki deck over Wi‑Fi. Etymology comes from a bundled offline dictionary.
- **Memorization** — LPCG-style overlapping *step* cards plus an optional *full recitation* card for poetry and prose, synced into `Memorize::Book::page` subdecks.

The plugin talks to [AnkiConnect](https://foosoft.net/projects/anki-connect/) on a PC on the same network. **Card defaults**, decks, note types, and one-tap send are editable on the device — no SSH or file editing required on Kobo.

**Requirements:** KOReader, Anki + AnkiConnect on a PC, StarDict dictionaries for Vocabulary Cards, and matching Anki note types (*Vocabulary Card* and *Memorization*).

---

## Before you publish (checklist)

- [ ] `configuration.lua` is **not** tracked (listed in `.gitignore`)
- [ ] Only `configuration.lua.sample` is committed (placeholders)
- [ ] No `*_settings.json`, `*_cards.json`, or `*.log` in the commit
- [ ] [LICENSE](../LICENSE) (MIT) is present
- [ ] [README.md](../README.md) and [docs/](README.md) are complete

Quick check (Git Bash or WSL):

```bash
git status
git check-ignore -v configuration.lua   # should show .gitignore rule
```

---

## Publish to GitHub (first time)

### 1. Create the repository on GitHub

1. Go to [github.com/new](https://github.com/new).
2. **Repository name:** `AnkiKoFlash.koplugin`
   (The `.koplugin` suffix helps KOReader AppStore and search.)
3. **Description:** paste the one-line description above.
4. **Public**
5. Do **not** add a README, .gitignore, or license — you already have them locally.
6. Create repository.

### 2. Initialize git locally (if not already)

Install [Git for Windows](https://git-scm.com/download/win) or use **GitHub Desktop**.

In Git Bash, WSL, or PowerShell (with Git on PATH), from the plugin folder:

```bash
cd /path/to/AnkiKoFlash.koplugin

git init
git add .
git status   # confirm configuration.lua is NOT staged
git commit -m "Initial release: dictionary vocab and memorization cards for Anki via KOReader"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/AnkiKoFlash.koplugin.git
git push -u origin main
```

**GitHub Desktop:** File → Add local repository → select this folder → Publish repository.

### 3. Set the About section and topics

On the repo page → **⚙ Settings** (or pencil icon next to About):

| Field | Value |
|-------|--------|
| **Description** | One-line description (above) |
| **Website** | Link to `docs/getting-started.md` on GitHub, or your docs site |
| **Topics** | See topic list below |

**Recommended GitHub topics** (add as many as apply):

```
koreader-plugin
koplugin
koreader
anki
anki-connect
flashcards
spaced-repetition
vocabulary
etymology
memorization
e-reader
ebook
e-ink
kobo
kindle
lua
language-learning
```

The topic **`koreader-plugin`** is required for the [KOReader AppStore](https://github.com/omer-faruq/appstore.koplugin) to index your repo automatically.

### 4. Create a release (recommended)

Users and the AppStore expect tagged releases.

**One-command release (recommended):**

```powershell
# First time on this machine:
gh auth login

# From the plugin repo:
.\release.ps1                  # bump patch, zip, tag, push, publish
.\release.ps1 -PublishOnly     # upload zip for current _meta.lua version
```

On WSL/Linux:

```bash
gh auth login
bash release.sh
bash release.sh --publish-only
```

The script builds `../AnkiKoFlash-vX.Y.Z.zip` with `AnkiKoFlash.koplugin/` at the top level (via `git archive`), bumps `_meta.lua` unless you pass a version, tags `vX.Y.Z`, pushes, and publishes the GitHub Release with `gh`.

**Manual release:**

1. GitHub → **Releases → Create a new release**
2. **Tag:** `v1.0.0` (match `version` in [`_meta.lua`](../_meta.lua))
3. **Title:** `v1.0.0 — dictionary vocab + memorization for Anki`
4. **Description:** short changelog + link to [Getting started](getting-started.md)
5. **Attach assets:** zip the plugin folder contents so the zip contains `AnkiKoFlash.koplugin/` at the top level:

   ```bash
   # From parent directory of the plugin folder
   zip -r AnkiKoFlash-v1.0.0.zip AnkiKoFlash.koplugin \
     -x "*.git*" -x "*configuration.lua" -x "*_settings.json" -x "*_cards.json" -x "*.log"
   ```

   On Windows: right-click the folder → Send to → Compressed folder, after confirming secrets are not inside.

6. Publish release.

Bump `_meta.lua` `version` whenever you tag a new release.

### 5. Enable Issues (optional but helpful)

Settings → General → Features → enable **Issues** so users can report bugs without email.

---

## How people find KOReader plugins

### 1. KOReader AppStore (highest impact for KOReader users)

Install [appstore.koplugin](https://github.com/omer-faruq/appstore.koplugin) on the device, or browse [the web catalog](https://omer-faruq.github.io/appstore.koplugin/).

Your repo is discovered if:

- GitHub topic **`koreader-plugin`** is set
- Repo is **public**
- Name ends with **`.koplugin`** (you already match)

If it does not appear immediately: AppStore → **Install plugin from URL** → enter `YOUR_USERNAME/AnkiKoFlash.koplugin`.

### 2. GitHub search

People search for `koreader anki`, `koplugin flashcards`, `anki connect koreader`. Help matching by using those phrases naturally in:

- Repository **name** and **description**
- **README** first paragraph (already done)
- **Topics** (above)

### 3. Anki and language-learning communities

Share once where it fits (read each community's rules first):

| Place | Angle |
|-------|--------|
| [r/Anki](https://www.reddit.com/r/Anki/) | Reading on e-ink → vocab cards + AnkiConnect workflow |
| [r/koreader](https://www.reddit.com/r/koreader/) | New plugin announcement |
| [Anki Forums](https://forums.ankiweb.net/) | "KOReader to Anki" setup thread |
| KOReader [GitHub Discussions](https://github.com/koreader/koreader/discussions) | Plugin showcase |

Include: one-line pitch, link to repo, link to [Getting started](getting-started.md), and note that Anki note types must be set up once.

### 4. Awesome lists and wikis

Search GitHub for `awesome koreader` or `awesome anki` and open a PR to add your repo if a list exists. KOReader's wiki may have a third-party plugins page — check [koreader/koreader wiki](https://github.com/koreader/koreader/wiki).

### 5. README polish for search engines

GitHub README is indexed by Google. Already helpful:

- Product name in the `#` title
- Words: KOReader, Anki, AnkiConnect, Kobo, Kindle, flashcards, vocabulary, etymology, memorization
- Links to official KOReader and Anki sites

**Optional upgrades:**

- Add 2–3 **screenshots** (highlight menu, card preview, Anki card) under `docs/images/` and embed in README
- Add a **"Compare"** line: "Unlike exporting highlights manually, this plugin builds finished cards on-device and sends via AnkiConnect"

### 6. Consistent naming everywhere

| Location | Name |
|----------|------|
| GitHub repo | `AnkiKoFlash.koplugin` |
| Folder on device | `AnkiKoFlash.koplugin/` |
| `_meta.lua` `fullname` | `AnkiKoFlash` |
| `_meta.lua` `name` | `ankikoflash` (internal id) |

On-device data files: `ankikoflash_cards.json`, `ankikoflash_settings.json` (migrated automatically from older filenames).

---

## After publishing

- [ ] Verify raw GitHub URL works: `https://github.com/YOUR_USERNAME/AnkiKoFlash.koplugin`
- [ ] Test install from release zip on emulator (`bash start.sh`)
- [ ] Search GitHub for `topic:koreader-plugin anki` and confirm your repo appears
- [ ] Open AppStore on device → refresh → find your plugin (or install from URL once)
- [ ] Watch **Issues** and tag fixes as `v1.1.1`, etc.

---

## Updating the plugin

```bash
git add .
git commit -m "Describe what changed"
git push

# New release (one command)
gh auth login   # first time only
bash release.sh
```

Or on Windows PowerShell: `.\release.ps1`

Update `_meta.lua` `version` to match the tag (the release script does this automatically when bumping).

---

## Related docs

- [Getting started](getting-started.md) — user install path (link this in releases)
- [Plugin configuration](plugin-configuration.md) — settings reference
- [Documentation index](README.md)
