# NextChat Desktop RCE via Plugin XSS — PoC

**CVE:** Pending assignment  
**CWE:** CWE-79 (Stored/DOM XSS) → CWE-78 (OS Command Execution)  
**CVSS 3.1:** 8.6 High — `AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:H`  
**Affected:** NextChat Desktop (Tauri) ≤ 2.16.1 (all platforms: Windows, macOS, Linux)

---

## Summary

A stored XSS in the plugin editor (`app/components/plugin.tsx:348`) combined
with a permissive Tauri desktop configuration allows a remote attacker to
achieve arbitrary file read/write and OS-level code execution on the victim's
machine. The only user interaction required is loading a plugin from an
attacker-controlled URL (one click).

## Root Cause

Three conditions combine to form the vulnerability:

| # | Condition | Location | Detail |
|---|-----------|----------|--------|
| 1 | **Unsanitized innerHTML** | `app/components/plugin.tsx:348` | `dangerouslySetInnerHTML={{ __html: editingPlugin.content }}` renders raw plugin content without any sanitization (no DOMPurify, no escaping) |
| 2 | **Unrestricted remote input** | `app/components/plugin.tsx:89-117` | `loadFromUrl()` fetches arbitrary URLs and stores the response text directly into `plugin.content` |
| 3 | **Permissive Tauri config** | `src-tauri/tauri.conf.json` | `withGlobalTauri: true` + `csp: null` + `fs.all: true` (no scope) |

## Attack Chain

```
Attacker crafts malicious OpenAPI YAML with <img onerror="..."> in a string field
    │
    ▼
Victim clicks "Load from URL" in NextChat Desktop plugin editor
    │
    ▼
loadFromUrl() fetches YAML, JSON.parse fails, raw text stored as plugin.content
    │
    ▼
dangerouslySetInnerHTML renders the YAML text including the <img> tag
    │
    ▼
Browser parses <img src=x>, image fails to load, onerror handler executes
    │
    ▼
JavaScript payload runs in WebView context with window.__TAURI__ available
    │
    ▼
window.__TAURI__.fs.writeTextFile() writes arbitrary file to OS filesystem
    │
    ▼
RCE achieved (e.g., write to OS autostart directory, overwrite binaries, etc.)
```

## Reproduction

### Prerequisites

- NextChat Desktop (Tauri build) — any version up to 2.16.1
  - Download from: https://github.com/ChatGPTNextWeb/ChatGPT-Next-Web/releases
- Python 3 (for the exploit server)
- Attacker and victim on the same network (or attacker server reachable)

### Step 1: Verify vulnerability conditions

```bash
bash poc/verify_vuln.sh .
```

All 6 conditions should show `[VULN]`.

### Step 2: Start the exploit server

```bash
# Stage 1 (default): Write proof file
python3 poc/exploit_server.py --port 8888

# Stage 2: Read /etc/hosts and exfiltrate to attacker
python3 poc/exploit_server.py --port 8888 --payload stage2

# Stage 3: Write Linux autostart persistence
python3 poc/exploit_server.py --port 8888 --payload stage3
```

### Step 3: Trigger in NextChat Desktop

1. Open the NextChat Desktop application (Tauri build)
2. Navigate to **Settings → Plugins**
3. Click **+** to create a new plugin
4. In the **"Load from URL"** field, enter:
   ```
   http://<attacker-ip>:8888/plugin.yaml
   ```
5. Click the **Load** button (reload icon)

### Step 4: Verify exploitation

**Stage 1 (file write):**
- A red banner appears in the app: `[PoC] RCE: Wrote /tmp/nextchat-poc.txt`
- File created at `/tmp/nextchat-poc.txt` (Linux/macOS) or `C:\nextchat-poc.txt` (Windows)

**Stage 2 (exfiltration):**
- The exploit server logs the contents of `/etc/hosts` (or Windows `hosts` file)
- Data is sent via Tauri HTTP API (bypasses browser CORS)

**Stage 3 (persistence):**
- File written to `~/.config/autostart/nextchat-poc.desktop`
- On next login, the autostart entry executes (shows a notification for PoC)

## Payload Stages

### Stage 1: Arbitrary File Write (`stage1_rce_file_write.yaml`)
Writes a proof-of-concept text file to the filesystem. Demonstrates that the
attacker can create files anywhere the Tauri process has permissions.

### Stage 2: Data Exfiltration (`stage2_exfiltrate.yaml`)
Reads a local file using `window.__TAURI__.fs.readTextFile()` and sends it to
the attacker's server using `window.__TAURI__.http.fetch()`, which bypasses
browser CORS restrictions entirely.

### Stage 3: OS Persistence (`stage3_persist_linux.yaml`)
Writes a `.desktop` file to the Linux autostart directory, achieving code
execution on every user login. Equivalent attacks exist for:
- **macOS:** `~/Library/LaunchAgents/` (LaunchAgent plist)
- **Windows:** `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\`

## Impact

- **Confidentiality (HIGH):** Read any file accessible to the user
- **Integrity (HIGH):** Write/overwrite any file accessible to the user
- **Availability (HIGH):** Delete critical files, corrupt system state
- **Scope Change (YES):** WebView sandbox → full OS filesystem

## Tauri APIs Available to Attacker

Given the current `tauri.conf.json` allowlist:

| API | Config | Capability |
|-----|--------|------------|
| `fs` | `all: true`, no scope | Read, write, delete any file |
| `http` | `all: true`, scope `*` | HTTP requests to any host (bypasses CORS) |
| `shell` | `open: true` | Open URLs in default browser (phishing) |
| `dialog` | `all: true` | Show native dialogs (social engineering) |
| `clipboard` | `all: true` | Read/write clipboard content |
| `notification` | `all: true` | Show OS notifications (social engineering) |

## Recommended Fixes

1. **Sanitize plugin content before rendering:**
   ```tsx
   import DOMPurify from 'dompurify';
   // ...
   dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(editingPlugin.content) }}
   ```
   Or better, use `textContent` instead of `innerHTML`:
   ```tsx
   <code ref={el => { if (el) el.textContent = editingPlugin.content; }} />
   ```

2. **Enable Content Security Policy in Tauri:**
   ```json
   "security": {
     "csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
   }
   ```

3. **Restrict filesystem scope:**
   ```json
   "fs": {
     "all": true,
     "scope": ["$APPDATA/*", "$RESOURCE/*"]
   }
   ```

4. **Disable withGlobalTauri in production:**
   ```json
   "withGlobalTauri": false
   ```

5. **Validate plugin schemas before storage:**
   Parse the content as YAML/JSON and validate it against the OpenAPI spec
   schema before storing. Reject content with HTML tags.

## Files

```
poc/
├── exploit_server.py                  # HTTP server with CORS + exfil logging
├── verify_vuln.sh                     # Checks vulnerability conditions in source
├── payloads/
│   ├── stage1_rce_file_write.yaml     # Proof file write
│   ├── stage2_exfiltrate.yaml         # Read file + exfiltrate
│   └── stage3_persist_linux.yaml      # Autostart persistence (Linux)
└── README.md                          # This file
```

## Timeline

- **2024-XX-XX:** Vulnerability discovered
- **2024-XX-XX:** PoC developed and verified
- **2024-XX-XX:** Vendor notified
- **2024-XX-XX:** CVE assigned (pending)
