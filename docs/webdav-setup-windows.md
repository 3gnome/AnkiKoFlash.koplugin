# WebDAV setup (Windows)

Run a small local WebDAV server on your PC so KOReader (and optional tools like the iPhone **Files** app) can sync highlight sidecars and read exported library files over your home Wi‑Fi.

This guide uses [hacdias/webdav](https://github.com/hacdias/webdav) with **no authentication** for simplicity on a trusted home network. Auth is disabled by design; KOReader Cloud storage+ and Files app leave username/password blank.

## Placeholders

Replace these when following the guide:

| Placeholder | Meaning |
|-------------|---------|
| `<WebDAV-root>` | Folder served as the WebDAV root (e.g. `%USERPROFILE%\Desktop\KOReader Highlights`) |
| `<LAN-IP>` | Your PC’s private-network IPv4 (from `ipconfig`, e.g. `192.168.x.x`) |
| `<PORT>` | TCP port for WebDAV (default **8181**) |

After `go install`, the server binary is typically at `%USERPROFILE%\go\bin\webdav.exe`.

## What you get

- One folder on disk = WebDAV root (sidecar `*.sdr.json`, optional `library/` for TagBank/Obsidian export)
- HTTP WebDAV on `<PORT>` bound to all interfaces (`0.0.0.0`)
- Windows Firewall inbound rule (**Private** profile only)
- Scheduled task **KOReader WebDAV** — starts at logon, **no visible terminal window**
- Writes enabled (`permissions: CRUD`) for KOReader upload/sync

## Prerequisites

- Windows 10 or 11
- PC and ereader on the **same Wi‑Fi** (home / private network)
- [Go](https://go.dev/dl/) installed
- [Tag Bank Highlight Sync](https://github.com/3gnome/tagbankhighlightsync.koplugin) (or compatible HighlightSync plugin) if you use cloud sync

Install the WebDAV server:

```powershell
go install github.com/hacdias/webdav/v5@latest
```

Confirm `%USERPROFILE%\go\bin\webdav.exe` exists.

## 1. Choose a WebDAV root folder

Create or pick a dedicated folder, for example:

```
%USERPROFILE%\Desktop\KOReader Highlights
```

KOReader lists **everything at the WebDAV root** in Cloud storage+. Keep the root lean:

- **Keep:** `*.sdr.json`, `library/`, setup files (`webdav.yaml`, `setup-webdav.*`)
- **Remove:** test probes, stray drafts, unrelated large files

## 2. Configuration — `webdav.yaml`

Save in `<WebDAV-root>` as UTF-8 **without BOM**:

```yaml
address: 0.0.0.0
port: 8181
auth: false
permissions: CRUD
```

On first start you may see:

```text
WARN unprotected config: no users have been set, so no authentication will be used
INFO listening {"address": "[::]:8181"}
```

That is **expected** with `auth: false` and no `users:` block.

## 3. Setup scripts (in `<WebDAV-root>`)

Three files live beside your data (not in the plugin repo):

| File | Role |
|------|------|
| `setup-webdav.ps1` | One-time repair: writes `webdav.yaml`, `start-webdav-hidden.vbs`, `run-webdav.ps1`, firewall rule, logon scheduled task, starts server hidden |
| `setup-webdav.cmd` | Double-click wrapper when PowerShell execution policy blocks `.ps1` |
| `start-webdav-hidden.vbs` | Hidden launcher (used by scheduled task and `run-webdav.ps1`) |
| `run-webdav.ps1` | Manual repair: runs `wscript.exe //B start-webdav-hidden.vbs` |

### Hidden start — use VBS, not `Start-Process -WindowStyle Hidden`

Do **not** launch `webdav.exe` with `&` (visible console) or `Start-Process -WindowStyle Hidden` (PowerShell exits 0 but the server often **does not stay running**).

Use **`start-webdav-hidden.vbs`** beside your config:

```vbscript
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = "<WebDAV-root>"
cmd = """" & "<path-to>\webdav.exe" & """ --config """ & "<WebDAV-root>\webdav.yaml" & """"
sh.Run cmd, 0, False
```

Window style **0** = hidden; **`False`** = do not wait (server keeps running).

### `run-webdav.ps1`

```powershell
$ErrorActionPreference = 'Stop'
$VbsPath = '<WebDAV-root>\start-webdav-hidden.vbs'
& wscript.exe //B $VbsPath
```

### `setup-webdav.ps1` (summary)

Your setup script should:

1. Ensure `<WebDAV-root>` exists
2. Write `webdav.yaml`, `start-webdav-hidden.vbs`, and `run-webdav.ps1`
3. Add firewall rule **KOReader WebDAV** — inbound TCP `<PORT>`, **Private** profile only
4. Register scheduled task **KOReader WebDAV** at logon:

   ```text
   wscript.exe //B "<WebDAV-root>\start-webdav-hidden.vbs"
   ```

5. Stop any existing `webdav.exe`, start via VBS, verify `Get-Process webdav` (warn if missing)

If task registration fails with *Access is denied*, run setup once from **Administrator** PowerShell. Config files are still rewritten and WebDAV starts even without admin.

### `setup-webdav.cmd`

```bat
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-webdav.ps1"
pause
```

## 4. One-time setup

```powershell
cd "<WebDAV-root>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\setup-webdav.ps1"
```

Or double-click **`setup-webdav.cmd`**.

## 5. KOReader Cloud storage+

On the ereader (same Wi‑Fi as the PC):

1. **Tools → Cloud storage+** → Add WebDAV account
2. **Address:** `http://<LAN-IP>:8181/` (replace `<LAN-IP>` with your PC’s LAN address)
3. **Username / password:** leave **empty**
4. **Tag Bank Highlight Sync → Cloud folder → Edit** → choose **`/`** (root)

On the **same PC**, you can use `http://127.0.0.1:8181/` instead of the LAN IP.

**WSL emulator:** If `curl http://127.0.0.1:8181/` fails from WSL, use `http://<LAN-IP>:8181/` or run `configure-emulator-webdav.sh` from the TagBank plugin repo (auto-detects a working URL).

## 6. Verify

```powershell
curl.exe http://127.0.0.1:8181/
Get-ScheduledTask -TaskName 'KOReader WebDAV'
Get-Process webdav -ErrorAction SilentlyContinue
```

Expect a WebDAV XML listing, task state **Running** (or **Ready**), and a `webdav` process. **No terminal window** should appear after logon.

Find `<LAN-IP>` on Windows:

```powershell
ipconfig
```

Use the **IPv4 Address** of your Wi‑Fi/Ethernet adapter (not `127.0.0.1`).

## 7. Reinstall / repair

From `<WebDAV-root>`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\setup-webdav.ps1"
```

This rewrites config, recreates the task and firewall rule (when permitted), and restarts WebDAV hidden.

## Troubleshooting

| Problem | What to check |
|---------|----------------|
| Task succeeds but WebDAV not running | Re-run setup — use `start-webdav-hidden.vbs`, not `Start-Process -WindowStyle Hidden`. Verify with `Get-Process webdav`. |
| Visible terminal on startup | Don’t start `webdav.exe` manually in a console. Scheduled task should run `wscript.exe //B start-webdav-hidden.vbs`. |
| `running scripts is disabled` | Use `setup-webdav.cmd` or `powershell -ExecutionPolicy Bypass -File .\setup-webdav.ps1` |
| Connection refused | Is `webdav` running? Is scheduled task registered? Re-run setup (Administrator if task registration failed). |
| Wrong files listed in KOReader | `webdav.yaml` must use `auth: false`; runner must set `-WorkingDirectory` to `<WebDAV-root>` |
| KOReader auth error | Leave username/password blank when `auth: false` |
| Upload / sync returns 403 | Add `permissions: CRUD` to `webdav.yaml`, restart WebDAV |
| `Access is denied` stopping webdav | End **webdav.exe** in Task Manager (or run setup as Administrator), then re-run setup |
| Files not syncing | Tag Bank → Cloud folder set? Cloud storage+ enabled on device? |
| WSL can’t reach `127.0.0.1:8181` | Use `http://<LAN-IP>:8181/` from WSL |

## Related

- [Getting started](getting-started.md) — AnkiKoFlash + AnkiConnect on the same LAN
- [Plugin configuration](plugin-configuration.md) — decks, note types, sync behavior
- Tag Bank Highlight Sync plugin — cloud folder, library export to `library/`

## Unrelated: Bookshelf / Cover Browser lag

Slow paging when scrolling through a large library in **[Bookshelf](https://github.com/AndyHazz/bookshelf.koplugin)** (with **CoverBrowser** enabled) is **not** caused by AnkiKoFlash or Tag Bank — neither plugin hooks library pagination. Bookshelf depends on CoverBrowser for covers and metadata; large libraries pay a per-page cache cost. Update Bookshelf, tune `cover_cache_mb` in Bookshelf settings, or temporarily disable Bookshelf to confirm.
