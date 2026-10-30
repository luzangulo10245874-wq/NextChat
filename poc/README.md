# NextChat Desktop RCE via Plugin XSS — PoC

**CVE:** Pending assignment
**CWE:** CWE-79 (Stored/DOM XSS) → CWE-78 (OS Command Execution)
**CVSS 4.0:** 8.4 High — `CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:A/VC:H/VI:H/VA:N/SC:H/SI:H/SA:H`
**CVSS 3.1:** 9.6 Critical — `CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:H`
**Affected:** NextChat Desktop (Tauri) ≤ 2.16.1 — Windows, macOS, Linux

---

## Summary

A stored XSS in the plugin editor (`app/components/plugin.tsx:348`) combined
with a permissive Tauri desktop configuration allows a remote attacker to
achieve arbitrary file read/write and OS-level code execution on the victim's
machine. The only user interaction required is loading a plugin from an
attacker-controlled URL (one click).

## Reproduction (< 5 minutes, no build required)

### What you need

| #  | Requirement            | How to get it |
|----|------------------------|---------------|
| 1  | NextChat Desktop (.exe/.dmg/.AppImage) | Download the **official release** from [GitHub Releases](https://github.com/ChatGPTNextWeb/ChatGPT-Next-Web/releases). Any version ≤ 2.16.1. |
| 2  | Python 3               | Pre-installed on macOS/Linux. On Windows: `winget install Python.Python.3.12` or [python.org](https://www.python.org/downloads/) |
| 3  | This `poc/` folder     | Already in this repository |

> **No compilation, no Rust, no Node.js, no yarn.** The official pre-built
> binary contains the identical vulnerable `tauri.conf.json`.

### Step 1 — Install NextChat Desktop

**Windows:**
```
NextChat_<version>_x64-setup.exe
```
Double-click the installer. Default options are fine.

**macOS:**
```
NextChat_<version>_x64.dmg
```
Open the .dmg, drag NextChat to Applications.

**Linux:**
```
NextChat_<version>_amd64.AppImage
chmod +x NextChat_*.AppImage
```

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

1. **Open NextChat Desktop**
2. Click the **gear icon** (Settings) in the bottom-left
3. Scroll down to **Plugins** and click it
4. Click the **"+"** button to create a new plugin
5. In the **"Load from URL"** input field, paste:
   ```
   http://<your-ip>:8888/plugin.yaml
   ```
   (Use the URL the exploit server printed, or `http://127.0.0.1:8888/plugin.yaml` if testing locally)
6. Click the **reload/load button** (circular arrows icon) next to the input

### Step 4 — Verify the result

**In the NextChat window:**
- A **red banner** appears at the top: `[PoC] RCE: Wrote C:\nextchat-poc.txt`
- The window title changes to `[PWNED] NextChat RCE`

**On the filesystem:**

Windows:
```
type C:\nextchat-poc.txt
```

macOS / Linux:
```
cat /tmp/nextchat-poc.txt
```

Expected contents:
```
[PoC] NextChat Desktop RCE via Plugin XSS
Timestamp: 2024-XX-XXTXX:XX:XXZ
Platform: Win32
UserAgent: Mozilla/5.0 ...
```

**In the exploit server terminal:**
```
  [+] Payload delivered: stage1_rce_file_write.yaml
      Target: 127.0.0.1
```

### Optional: Test data exfiltration (Stage 2)

Stop the server (Ctrl+C) and restart with:

```
python3 exploit_server.py --port 8888 --payload stage2
```

Repeat steps 3-4. The exploit server now logs the contents of the victim's
`hosts` file (`C:\Windows\System32\drivers\etc\hosts` or `/etc/hosts`)
under `[EXFILTRATION]`.

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
window.__TAURI__.fs.writeTextFile() writes arbitrary file to victim's OS
    │
    ▼
RCE achieved (write to autostart, overwrite binaries, exfiltrate data)
```

## Payload Stages

| Stage | File | What it does |
|-------|------|-------------|
| **1** (default) | `stage1_rce_file_write.yaml` | Writes proof file to `/tmp/nextchat-poc.txt` or `C:\nextchat-poc.txt` |
| **2** | `stage2_exfiltrate.yaml` | Reads `/etc/hosts` (or Windows hosts), exfiltrates to attacker via Tauri HTTP (bypasses CORS) |
| **3** | `stage3_persist_linux.yaml` | Writes `.desktop` autostart entry on Linux for login persistence |

## Impact

| Metric | Rating | Evidence |
|--------|--------|----------|
| **Confidentiality** | HIGH | `fs.readTextFile` reads any user-accessible file; `http.fetch` exfiltrates without CORS |
| **Integrity** | HIGH | `fs.writeTextFile`/`writeBinaryFile` writes anywhere (autostart dirs, binaries, configs) |
| **Availability** | HIGH | `fs.all: true` enables `removeFile`/`removeDir` — attacker can delete system files |
| **Scope Change** | YES | Crosses from WebView sandbox into host OS filesystem |

## Tauri APIs Exposed to Attacker

| API | Config | Capability |
|-----|--------|------------|
| `fs` | `all: true`, no scope | Read, write, delete any file |
| `http` | `all: true`, scope `*` | HTTP to any host (bypasses CORS) |
| `shell` | `open: true` | Open URLs in default browser |
| `dialog` | `all: true` | Show native dialogs |
| `clipboard` | `all: true` | Read/write clipboard |
| `notification` | `all: true` | Show OS notifications |

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
