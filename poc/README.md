# NextChat Desktop — Stored XSS to RCE via Plugin Editor (PoC)

**CVE:** Pending assignment
**CWE:** CWE-79 (Stored/DOM XSS) → CWE-78 (OS Command Injection) + CWE-200 (Information Disclosure) + CWE-918 (SSRF)
**CVSS 3.1:** 8.3 High — `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:L`
**Affected:** NextChat Desktop (Tauri) ≤ 2.15.8 — Windows, macOS, Linux

---

## Summary

A stored XSS in the plugin editor (`app/components/plugin.tsx:348`) combined
with a permissive Tauri desktop configuration (`withGlobalTauri: true`,
`csp: null`) allows a remote attacker to achieve **Remote Code Execution (RCE)**
through a file-write-to-Startup-folder chain:

### RCE Chain (confirmed on Windows)
1. **XSS** fires when victim loads a malicious plugin from attacker URL
2. **`dialog.save()`** opens a Save dialog defaulting to the **Windows Startup folder** with a social-engineered filename ("NextChat-Updater.bat")
3. User clicks **Save** (one click)
4. **`fs.writeTextFile()`** writes attacker-controlled `.bat` to the Startup folder
5. On next Windows login → **arbitrary commands execute automatically**

### Additional confirmed impacts (zero additional interaction):
- **Steal clipboard contents** silently (passwords, API keys, tokens)
- **Make arbitrary HTTP requests** from victim's machine (CORS bypass + SSRF)
- **Trigger OS protocol handlers** via `location.href`/`iframe.src` (ms-msdt, search-ms)
- **Send spoofed OS notifications** (phishing)
- **Crash/restart the app** via process.exit/relaunch (DoS)

---

## Reproduction (< 5 minutes, no build required)

### What you need

| #  | Requirement            | How to get it |
|----|------------------------|---------------|
| 1  | NextChat Desktop (.exe/.dmg/.AppImage) | Download **v2.15.8** from links below. **Do NOT use** nextchat.club — that is the commercial SaaS version with a different UI. |
| 2  | Python 3               | Pre-installed on macOS/Linux. On Windows: `winget install Python.Python.3.12` or [python.org](https://www.python.org/downloads/) |
| 3  | This `poc/` folder     | Already in this repository |

> **No compilation, no Rust, no Node.js, no yarn.** The official pre-built
> binary contains the identical vulnerable `tauri.conf.json`.

### Step 1 — Download and install NextChat Desktop (open-source Tauri build)

> **IMPORTANT:** Do NOT use the app from `nextchat.club` — that is the commercial
> SaaS version with a different UI that does not expose the plugin editor.
> You need the **open-source Tauri desktop build** from GitHub Releases.

**Direct download links (v2.15.8):**

| Platform | File | Link |
|----------|------|------|
| Windows (exe) | `NextChat_2.15.8_x64-setup.exe` (6.1 MB) | [Download](https://github.com/ChatGPTNextWeb/NextChat/releases/download/v2.15.8/NextChat_2.15.8_x64-setup.exe) |
| Windows (msi) | `NextChat_2.15.8_x64_en-US.msi` (6.6 MB) | [Download](https://github.com/ChatGPTNextWeb/NextChat/releases/download/v2.15.8/NextChat_2.15.8_x64_en-US.msi) |
| macOS (universal) | `NextChat_2.15.8_universal.dmg` (13.5 MB) | [Download](https://github.com/ChatGPTNextWeb/NextChat/releases/download/v2.15.8/NextChat_2.15.8_universal.dmg) |
| Linux (AppImage) | `next-chat_2.15.8_amd64.AppImage` (87.2 MB) | [Download](https://github.com/ChatGPTNextWeb/NextChat/releases/download/v2.15.8/next-chat_2.15.8_amd64.AppImage) |
| Linux (deb) | `next-chat_2.15.8_amd64.deb` (7.9 MB) | [Download](https://github.com/ChatGPTNextWeb/NextChat/releases/download/v2.15.8/next-chat_2.15.8_amd64.deb) |

**Install:**

- **Windows:** Double-click `NextChat_2.15.8_x64-setup.exe`. Default options are fine.
- **macOS:** Open `NextChat_2.15.8_universal.dmg`, drag NextChat to Applications.
- **Linux:** `chmod +x next-chat_2.15.8_amd64.AppImage && ./next-chat_2.15.8_amd64.AppImage`

### Step 2 — Start the exploit server

Open a terminal in this `poc/` directory:

```
python3 exploit_server.py --port 8888
```

On Windows (if `python3` is not recognized):
```
python exploit_server.py --port 8888
```

The server prints your local IP and the payload URL:

```
  Plugin URL: http://192.168.1.100:8888/plugin.yaml
```

Leave this terminal open.

### Step 3 — Trigger the exploit

1. **Open NextChat Desktop** (the open-source Tauri build, NOT nextchat.club)
2. In the sidebar, click **"Discovery"** (compass icon, next to "Mask")
3. A popup selector appears — click **"Plugin"**
4. On the Plugins page, click **"Create"** (top-right)
5. In the **"Edit Plugin"** modal, find the **"OpenAPI Schema"** row
6. Paste the payload URL in the text input field:
   ```
   http://<your-ip>:8888/plugin.yaml
   ```
   (Use the URL the exploit server printed, or `http://127.0.0.1:8888/plugin.yaml` if testing locally)
7. Click the **"Load From URL"** button next to the input

### Step 4 — Verify the result

**In the NextChat window:**
- A **red banner** appears at the top: `[PoC] Clipboard stolen and exfiltrated to attacker server`
- The window title changes to `[PWNED] NextChat XSS`

**In the exploit server terminal:**
```
  ==========================================================
  [EXFILTRATION] POST from 127.0.0.1
  Clipboard: <whatever text was on the victim's clipboard>
  Platform: Win32
  Timestamp: 2026-10-30T...
  ==========================================================
```

The victim's **clipboard contents** (passwords, API keys, tokens, etc.) are
silently read and exfiltrated to the attacker's server — no user interaction
beyond the initial plugin load.

### Optional: Test with diagnostic payload (Stage 0)

To see detailed information about which Tauri APIs are accessible:

```
python3 exploit_server.py --port 8888 --payload stage0
```

This shows an alert listing the full `__TAURI__` API surface available to the attacker.

---

## Root Cause

Three conditions combine to form the vulnerability:

| # | Condition | Location | Detail |
|---|-----------|----------|--------|
| 1 | **Unsanitized innerHTML** | `app/components/plugin.tsx:348` | `dangerouslySetInnerHTML={{ __html: editingPlugin.content }}` renders raw plugin content with zero sanitization |
| 2 | **Unrestricted remote input** | `app/components/plugin.tsx:89-117` | `loadFromUrl()` fetches arbitrary URLs and stores response text directly into `plugin.content` |
| 3 | **Permissive Tauri config** | `src-tauri/tauri.conf.json` | `withGlobalTauri: true` + `csp: null` + `clipboard.all: true` + `http.all: true` + `fs.all: true` + `dialog.all: true` |

## Attack Chains

### Chain 1 — RCE via Startup Folder (Windows)

```
Attacker hosts malicious OpenAPI YAML with <img onerror="..."> payload
    |
    v
Victim loads plugin URL in NextChat -> XSS fires
    |
    v
dialog.save() opens with defaultPath = Startup folder, titled "Save NextChat Auto-Updater"
    |
    v
User clicks Save (social engineering: looks like a legitimate app update)
    |
    v
fs.writeTextFile() writes .bat with attacker commands to Startup folder
    |
    v
Next Windows login -> .bat auto-executes -> ARBITRARY COMMAND EXECUTION (RCE)
```

**Confirmed path:** `C:\Users\Juan_\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\NextChat-Updater.bat`

### Chain 2 — File Write + Protocol Handler (Windows)

```
XSS fires
    |
    +--> dialog.save() writes .bat to C:\Users\Public\Desktop\ (visible to all users)
    |
    +--> iframe.src = "search-ms:..." triggers "Open Windows Explorer?" prompt
    |
    v
User clicks Open -> Explorer shows the .bat -> user double-clicks -> RCE
```

### Chain 3 — Silent Data Theft (all platforms)

```
XSS fires -> clipboard.readText() -> http.fetch() exfiltrates to attacker
    (zero interaction, completely silent)
```

### Chain 4 — Protocol Handler Trigger (Windows)

```
XSS fires -> location.href or iframe.src with ms-msdt:/search-ms: protocol
    |
    v
Windows shows "This site is trying to open..." prompt
    |
    v
User clicks Open -> protocol handler executes (ms-msdt Follina on unpatched systems)
```

---

## Exhaustive Impact Assessment (tested on v2.15.8 Windows — 60+ vectors across 12 rounds)

### Confirmed — Remote Code Execution

| # | Attack | Status | Detail |
|---|--------|--------|--------|
| 1 | **RCE via Startup folder write** | **CONFIRMED** | `dialog.save()` defaults to Startup folder + `fs.writeTextFile()` writes .bat → auto-executes on next login. Requires 1 click (Save dialog). |
| 2 | **File write to Public Desktop** | **CONFIRMED** | Wrote `NextChat-Update.bat` and `NextChat-Update.url` to `C:\Users\Public\Desktop\` — visible to all users on machine |
| 3 | **File write to user Documents** | **CONFIRMED** | Wrote `poc-test.bat` to `C:\Users\Juan_\OneDrive\Documents\` |

### Confirmed — No User Interaction Beyond Initial Load

| # | Attack | Status | Detail |
|---|--------|--------|--------|
| 4 | **Stored XSS** | CONFIRMED | `<img onerror>` executes JavaScript in Tauri WebView |
| 5 | **`__TAURI__` full API access** | CONFIRMED | 19 modules exposed via `withGlobalTauri: true` |
| 6 | **Clipboard theft** | CONFIRMED | `clipboard.readText()` silently reads clipboard without any prompt |
| 7 | **HTTP CORS bypass** | CONFIRMED | `http.fetch()` makes arbitrary HTTP requests from victim's IP |
| 8 | **SSRF via stream_fetch** | CONFIRMED | Custom Rust command with no URL validation — reached localhost:3000 |
| 9 | **Notification spoofing** | CONFIRMED | `notification.sendNotification()` sends fake OS notifications |
| 10 | **DoS — process.exit** | CONFIRMED | `process.exit()` and `process.relaunch()` available |
| 11 | **URL opening** | CONFIRMED | `shell.open('https://...')` opens attacker URL in default browser |
| 12 | **CVE-2024-35222 iframe IPC** | CONFIRMED | iframe gets full `__TAURI__` access including shell module |

### Confirmed — Protocol Handler Triggers (Windows, requires 1 click on OS prompt)

| # | Attack | Status | Detail |
|---|--------|--------|--------|
| 13 | **ms-msdt via location.href** | CONFIRMED | Triggers "This site is trying to open Diagnostics Troubleshooting Wizard" OS prompt |
| 14 | **ms-msdt via iframe.src** | CONFIRMED | Same prompt, doesn't navigate main page |
| 15 | **search-ms via iframe.src** | CONFIRMED | Triggers "This site is trying to open Windows Explorer" OS prompt |

### Blocked by Tauri Allowlist / Scope

| # | Attack | Status | Detail |
|---|--------|--------|--------|
| 16 | shell.Command execute/spawn | BLOCKED | `shell.all: false` — not in allowlist |
| 17 | shell.open with executables | BLOCKED | Regex rejects non-URL arguments |
| 18 | shell.open with file paths | BLOCKED | Regex: `^((mailto:\w+)\|(tel:\w+)\|(https?://\w+)).+` |
| 19 | shell.open with openWith param | BLOCKED | "unknown program name" for cmd/explorer/powershell/mshta |
| 20 | Direct fs read/write (no dialog) | BLOCKED | Empty default scope blocks all paths and all BaseDirectory values |
| 21 | os module (tempdir/platform/arch) | BLOCKED | Os module not in allowlist |
| 22 | WebviewWindow creation | BLOCKED | Requires window-create permission not in allowlist |

### Tauri APIs Available to Attacker

| API | Config | Exploitable | Impact |
|-----|--------|-------------|--------|
| `clipboard` | `all: true` | **YES — silent** | Read/write clipboard (steal passwords, tokens) |
| `http` | `all: true`, scope `http://* https://*` | **YES — silent** | Arbitrary HTTP from victim IP (CORS bypass, SSRF) |
| `notification` | `all: true` | **YES — silent** | Fake OS notifications (phishing) |
| `process` | via `withGlobalTauri` | **YES — silent** | `exit()` crashes app, `relaunch()` restarts it (DoS) |
| `dialog` | `all: true` | **YES — 1 click** | `save()` returns user-approved path, bypasses fs scope |
| `fs` | `all: true`, empty scope | **YES — via dialog** | Write via dialog.save() path; direct read/write blocked by scope |
| `shell` | `open: true` | **Partial** | Only https/http/mailto/tel URLs; executables and file paths blocked |
| `updater` | `active: true` | **Enumerated** | checkUpdate/installUpdate available but endpoint broken |
| `app` | via `withGlobalTauri` | **Info leak** | getName=NextChat, getVersion=2.15.8, getTauriVersion=1.5.4 |
| `event` | via `withGlobalTauri` | **YES** | emit/listen/once — can emit tauri:// events |
| `window` | partial | Low | close, hide, minimize, maximize available |

---

### CVSS Scoring

**CVSS 3.1:** 8.3 High — `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:L`

| Metric | Value | Rationale |
|--------|-------|-----------|
| Attack Vector | Network | Attacker hosts malicious URL |
| Attack Complexity | Low | Single click to load plugin, one more click on save dialog |
| Privileges Required | None | No authentication needed |
| User Interaction | Required | Victim must load plugin URL + click Save on dialog |
| Scope | Changed | Escapes WebView into OS: clipboard, network, filesystem, Startup auto-exec |
| Confidentiality | High | Clipboard silently stolen; SSRF reaches internal services; file listing via search-ms |
| Integrity | High | Can write arbitrary files to Startup folder (auto-exec RCE), Public Desktop, Documents |
| Availability | Low | process.exit() can crash the app |

---

## Payload Stages

| Stage | File | What it does |
|-------|------|-------------|
| **0** | `stage0_diagnostic.yaml` | Shows alert with full `__TAURI__` API surface and capability test results |
| **1** (default) | `stage1_clipboard_exfil.yaml` | Steals clipboard contents and exfiltrates via Tauri HTTP |
| **1-fs** | `stage1_rce_file_write.yaml` | File write via dialog.save() + fs.writeTextFile() |
| **1-dialog** | `stage1_rce_dialog_write.yaml` | File write using dialog.save() scope bypass |
| **rce** | `rce_bruteforce.yaml` | Systematic test of all command execution vectors (12 rounds) |
| **2** | `stage2_exfiltrate.yaml` | Read file + exfiltrate (blocked by empty scope) |
| **3** | `stage3_persist_linux.yaml` | Autostart persistence — Linux (blocked by empty scope) |

## Recommended Fixes

1. **Replace innerHTML with textContent (Critical):**
   ```tsx
   <code ref={el => { if (el) el.textContent = editingPlugin.content; }} />
   ```

2. **Enable CSP in Tauri (Critical):**
   ```json
   "csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
   ```

3. **Disable `withGlobalTauri` in production (High):**
   ```json
   "withGlobalTauri": false
   ```

4. **Add URL validation to `stream_fetch` (Medium):**
   Block `localhost`, `127.0.0.1`, `169.254.169.254`, and private IP ranges.

5. **Restrict clipboard API (Medium):**
   ```json
   "clipboard": { "all": false, "writeText": true }
   ```

6. **Add fs scope restrictions (Medium):**
   Define explicit scope paths instead of relying on dialog.save() dynamic scoping.

## Files

```
poc/
├── exploit_server.py                  # HTTP server with CORS + exfil logging
├── verify_vuln.sh                     # Checks vuln conditions in source
├── payloads/
│   ├── stage0_diagnostic.yaml         # Diagnostic: enumerate all Tauri APIs
│   ├── stage1_clipboard_exfil.yaml    # Clipboard theft + exfiltration
│   ├── stage1_rce_dialog_write.yaml   # File write via dialog.save()
│   ├── stage1_rce_file_write.yaml     # Direct file write (blocked by scope)
│   ├── rce_bruteforce.yaml            # Systematic command exec testing (12 rounds)
│   ├── stage2_exfiltrate.yaml         # File read + exfiltrate
│   └── stage3_persist_linux.yaml      # Linux persistence
├── build-desktop.sh                   # Build helper (bash)
├── build-desktop.ps1                  # Build helper (PowerShell)
└── README.md                          # This file
```
