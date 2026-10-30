#!/usr/bin/env bash
# NextChat Desktop RCE PoC — Vulnerability Condition Verifier
# Checks that the three required conditions exist in the source tree.
#
# Usage: bash verify_vuln.sh [path-to-nextchat-repo]

set -euo pipefail

REPO="${1:-.}"
PASS=0
FAIL=0

green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

check() {
    local label="$1" file="$2" pattern="$3"
    if grep -qPzo "$pattern" "$REPO/$file" 2>/dev/null; then
        green "  [VULN]  $label"
        PASS=$((PASS + 1))
    else
        red   "  [SAFE]  $label"
        FAIL=$((FAIL + 1))
    fi
}

bold ""
bold "  NextChat RCE — Vulnerability Condition Check"
bold "  Repo: $(cd "$REPO" && pwd)"
bold ""

bold "  1. XSS Sink (dangerouslySetInnerHTML on plugin content)"
check \
    "plugin.tsx uses dangerouslySetInnerHTML with editingPlugin.content" \
    "app/components/plugin.tsx" \
    '(?s)dangerouslySetInnerHTML.*editingPlugin\.content'

bold ""
bold "  2. No input sanitization on loadFromUrl"
if ! grep -qiP 'sanitiz|purify|escape|DOMPurify|xss' "$REPO/app/components/plugin.tsx" 2>/dev/null; then
    green "  [VULN]  No sanitization found in plugin.tsx"
    PASS=$((PASS + 1))
else
    red   "  [SAFE]  Sanitization detected in plugin.tsx"
    FAIL=$((FAIL + 1))
fi

bold ""
bold "  3. Tauri: withGlobalTauri = true"
check \
    "build.withGlobalTauri is true" \
    "src-tauri/tauri.conf.json" \
    '"withGlobalTauri"\s*:\s*true'

bold ""
bold "  4. Tauri: CSP disabled (null)"
check \
    "security.csp is null" \
    "src-tauri/tauri.conf.json" \
    '"csp"\s*:\s*null'

bold ""
bold "  5. Tauri: fs.all = true (unrestricted filesystem)"
check \
    "allowlist.fs.all is true" \
    "src-tauri/tauri.conf.json" \
    '(?s)"fs"\s*:\s*\{[^}]*"all"\s*:\s*true'

bold ""
bold "  6. Tauri: http.all = true (unrestricted HTTP for exfil)"
check \
    "allowlist.http.all is true" \
    "src-tauri/tauri.conf.json" \
    '(?s)"http"\s*:\s*\{[^}]*"all"\s*:\s*true'

bold ""
bold "  ──────────────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
    red   "  RESULT: ALL $PASS/$PASS CONDITIONS MET — VULNERABLE"
else
    green "  RESULT: $FAIL condition(s) not met — may be patched"
fi
bold "  ──────────────────────────────────────────"
bold ""
