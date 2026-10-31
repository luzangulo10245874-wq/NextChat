# NextChat Desktop — Stored XSS via Plugin Editor (PoC)

**CVE:** Pending assignment
**CWE:** CWE-79 (Stored/DOM XSS) → CWE-200 (Information Disclosure) + CWE-918 (SSRF)
**CVSS 3.1:** 7.6 High — `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:L/A:L`
**Affected:** NextChat Desktop (Tauri) ≤ 2.15.8 — Windows, macOS, Linux

---

## Summary

A stored XSS in the plugin editor (`app/components/plugin.tsx:348`) combined
with a permissive Tauri desktop configuration (`withGlobalTauri: true`,
`csp: null`) allows a remote attacker to:

1. **Steal clipboard contents** silently (passwords, API keys, tokens)
2. **Make arbitrary HTTP requests** from the victim's machine (CORS bypass + SSRF to internal network/cloud metadata)
3. **Write arbitrary files** to user-chosen locations via dialog.save() (one additional click)
4. **Send spoofed OS notifications** (phishing)
5. **Crash/restart the app** via process.exit/relaunch (DoS)

The only user interaction required is loading a plugin from an attacker-controlled URL (one click on "Load From URL").

Direct OS command execution (RCE) is **not possible** — the Tauri `shell` allowlist
(`shell.all: false`) blocks `Command.execute()` and `Command.spawn()`, and `shell.open()`
validates against a regex that only allows `https://`, `http://`, and `mailto:` URLs.

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
| 3 | **Permissive Tauri config** | `src-tauri/tauri.conf.json` | `withGlobalTauri: true` + `csp: null` + `clipboard.all: true` + `http.all: true` + `fs.all: true` |

## Attack Chain

```
Attacker hosts malicious OpenAPI YAML with <img onerror="..."> payload
    |
    v
Victim pastes URL in NextChat plugin editor -> clicks Load
    |
    v
loadFromUrl() fetches YAML -> JSON.parse fails -> raw text stored as plugin.content
    |
    v
dangerouslySetInnerHTML renders the entire YAML including the <img> tag as HTML
    |
    v
Browser fires onerror -> JavaScript executes in Tauri WebView context
    |
    v
window.__TAURI__.clipboard.readText() steals clipboard contents
    |
    v
window.__TAURI__.http.fetch() exfiltrates data to attacker (bypasses CORS)
    |
    v
Attacker receives victim's clipboard (passwords, API keys, tokens, etc.)
```

---

## Exhaustive Impact Assessment (tested on v2.15.8 Windows)

### Confirmed — No User Interaction Beyond Initial Load

| # | Attack | Status | Detail |
|---|--------|--------|--------|
| 1 | **Stored XSS** | CONFIRMED | `<img onerror>` executes JavaScript in Tauri WebView |
| 2 | **`__TAURI__` full API access** | CONFIRMED | 19 modules: app, cli, clipboard, dialog, event, fs, globalShortcut, http, invoke, notification, os, path, process, shell, tauri, updater, window, convertFileSrc, transformCallback |
| 3 | **Clipboard theft** | CONFIRMED | `clipboard.readText()` silently reads clipboard without any prompt |
| 4 | **HTTP CORS bypass** | CONFIRMED | `http.fetch()` makes arbitrary HTTP requests from victim's IP (bypasses same-origin, reaches internal network) |
| 5 | **SSRF via stream_fetch** | CONFIRMED | Custom Rust command with no URL validation — `stream_fetch({url:'http://127.0.0.1:3000/'})` returned status 200 |
| 6 | **Notification spoofing** | CONFIRMED | `notification.sendNotification()` sends fake OS notifications (phishing vector) |
| 7 | **DoS — process.exit** | CONFIRMED | `process.exit` and `process.relaunch` are available as callable functions |
| 8 | **URL opening** | CONFIRMED | `shell.open('https://...')` opens attacker URL in default browser |

### Confirmed — Requires One Additional User Click

| # | Attack | Status | Detail |
|---|--------|--------|--------|
| 9 | **Arbitrary file write** | CONFIRMED | `dialog.save()` shows "Save As" dialog -> user clicks Save -> `fs.writeTextFile()` writes attacker-controlled content. Successfully wrote `poc-test.bat` to `C:\Users\...\Documents\` |

### Blocked by Tauri Allowlist

| # | Attack | Status | Detail |
|---|--------|--------|--------|
| 10 | **shell.Command execute/spawn** | BLOCKED | `shell.all: false` — "not in the allowlist" for all variants (calc, cmd, powershell, notepad, sidecar) |
| 11 | **shell.open with executables** | BLOCKED | `shell.open('calc.exe')` — "Scoped command argument" rejected |
| 12 | **shell.open with file paths** | BLOCKED | Regex `^((mailto:\w+)|(https?://...))` only allows mailto/http/https |
| 13 | **shell.open with protocols** | BLOCKED | `file://`, `ms-msdt:` with args all fail regex validation |
| 14 | **invoke plugin:shell** | BLOCKED | "plugin shell not found" — shell IPC handler not registered |
| 15 | **Direct fs read/write** | BLOCKED | Empty default scope blocks all paths and all BaseDirectory values |

### Tauri APIs Available to Attacker

| API | Config | Exploitable | Impact |
|-----|--------|-------------|--------|
| `clipboard` | `all: true` | **YES — silent** | Read/write clipboard (steal passwords, tokens) |
| `http` | `all: true`, scope `http://* https://*` | **YES — silent** | Arbitrary HTTP from victim IP (CORS bypass, SSRF) |
| `notification` | `all: true` | **YES — silent** | Fake OS notifications (phishing) |
| `process` | via `withGlobalTauri` | **YES — silent** | `exit()` crashes app, `relaunch()` restarts it (DoS) |
| `dialog` | `all: true` | **YES — 1 click** | `save()` returns user-approved path, bypasses fs scope |
| `fs` | `all: true`, empty scope | **Partial** | Write via dialog.save() path only; direct read/write blocked |
| `shell` | `open: true` | **Partial** | Only https/http/mailto URLs; executables and file paths blocked |
| `updater` | `active: true` | **Enumerated** | `checkUpdate`, `installUpdate`, `onUpdaterEvent` available |
| `window` | partial | low | close, hide, minimize, maximize available |

---

### CVSS Scoring

**CVSS 3.1:** 7.6 High — `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:L/A:L`

| Metric | Value | Rationale |
|--------|-------|-----------|
| Attack Vector | Network | Attacker hosts malicious URL |
| Attack Complexity | Low | Single click to load plugin |
| Privileges Required | None | No authentication needed |
| User Interaction | Required | Victim must load the plugin URL |
| Scope | Changed | Escapes WebView into OS clipboard, network, filesystem, notifications |
| Confidentiality | High | Clipboard silently stolen (may contain passwords/tokens); SSRF reaches internal services |
| Integrity | Low | Can write files (with dialog interaction), send spoofed notifications, open URLs |
| Availability | Low | process.exit() can crash the app |

---

## Payload Stages

| Stage | File | What it does |
|-------|------|-------------|
| **0** | `stage0_diagnostic.yaml` | Shows alert with full `__TAURI__` API surface and capability test results |
| **1** (default) | `stage1_clipboard_exfil.yaml` | Steals clipboard contents and exfiltrates via Tauri HTTP |
| **1-fs** | `stage1_rce_file_write.yaml` | File write via dialog.save() + fs.writeTextFile() |
| **1-dialog** | `stage1_rce_dialog_write.yaml` | File write using dialog.save() scope bypass |
| **rce** | `rce_bruteforce.yaml` | Systematic test of all command execution vectors |
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
│   ├── rce_bruteforce.yaml            # Systematic command exec testing
│   ├── stage2_exfiltrate.yaml         # File read + exfiltrate
│   └── stage3_persist_linux.yaml      # Linux persistence
├── build-desktop.sh                   # Build helper (bash)
├── build-desktop.ps1                  # Build helper (PowerShell)
└── README.md                          # This file
```
