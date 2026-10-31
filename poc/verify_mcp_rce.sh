#!/usr/bin/env bash
# NextChat MCP RCE — Vulnerability Condition Verifier
# Checks that the RCE conditions exist in the source tree.
#
# This covers the SERVER-SIDE RCE via addMcpServer Server Action,
# which is separate from the desktop XSS vector.
#
# Usage: bash verify_mcp_rce.sh [path-to-nextchat-repo]

set -euo pipefail

REPO="${1:-.}"
PASS=0
FAIL=0

green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

check() {
    local label="$1" file="$2" pattern="$3"
    if grep -qP "$pattern" "$REPO/$file" 2>/dev/null; then
        green "  [VULN]  $label"
        PASS=$((PASS + 1))
    else
        red   "  [SAFE]  $label"
        FAIL=$((FAIL + 1))
    fi
}

check_absent() {
    local label="$1" file="$2" pattern="$3"
    if ! grep -qP "$pattern" "$REPO/$file" 2>/dev/null; then
        green "  [VULN]  $label"
        PASS=$((PASS + 1))
    else
        red   "  [SAFE]  $label"
        FAIL=$((FAIL + 1))
    fi
}

bold ""
bold "  NextChat MCP RCE — Server-Side Vulnerability Check"
bold "  Repo: $(cd "$REPO" && pwd)"
bold ""
bold "  ═══════════════════════════════════════════════════"
bold "  VECTOR: addMcpServer Server Action → child_process.spawn()"
bold "  ═══════════════════════════════════════════════════"

bold ""
bold "  1. Server Actions exposed (\"use server\" module)"
check \
    "app/mcp/actions.ts uses 'use server' — all exports are HTTP-callable" \
    "app/mcp/actions.ts" \
    '^"use server"'

bold ""
bold "  2. addMcpServer exported (callable over HTTP)"
check \
    "addMcpServer is an exported async function" \
    "app/mcp/actions.ts" \
    'export async function addMcpServer'

bold ""
bold "  3. ServerConfig.command is unsanitized (no allowlist)"
check_absent \
    "No command allowlist/validation in createClient" \
    "app/mcp/client.ts" \
    'allowlist|whitelist|allowedCommands|validCommand|sanitize'

bold ""
bold "  4. StdioClientTransport uses config.command directly"
check \
    "createClient passes config.command to StdioClientTransport" \
    "app/mcp/client.ts" \
    'command:\s*config\.command'

bold ""
bold "  5. ServerConfig type allows arbitrary command string"
check \
    "ServerConfig.command is an unvalidated string type" \
    "app/mcp/types.ts" \
    'command:\s*string'

bold ""
bold "  6. Auth uses shared access code (not a separate MCP secret)"
if grep -qP 'md5\.hash\(accessCode' "$REPO/app/mcp/actions.ts" 2>/dev/null; then
    if grep -qP 'process\.env\.CODE' "$REPO/app/mcp/actions.ts" 2>/dev/null; then
        yellow "  [WEAK]  Auth uses shared app CODE — any user can spawn commands"
        PASS=$((PASS + 1))
    fi
else
    if grep -qP 'assertMcp' "$REPO/app/mcp/actions.ts" 2>/dev/null; then
        red "  [SAFE]  Has auth check (examine manually)"
        FAIL=$((FAIL + 1))
    else
        green "  [VULN]  NO authentication check at all (pre-fix version!)"
        PASS=$((PASS + 1))
    fi
fi

bold ""
bold "  7. Default build mode is standalone (Server Actions work)"
check \
    "next.config.mjs defaults to standalone mode (not export)" \
    "next.config.mjs" \
    'BUILD_MODE.*standalone'

bold ""
bold "  ═══════════════════════════════════════════════════"
bold "  ADDITIONAL VECTORS"
bold "  ═══════════════════════════════════════════════════"

bold ""
bold "  8. SSRF via /api/proxy/ — X-Base-URL header unsanitized"
check \
    "proxy.ts uses X-Base-URL directly in fetch URL (no validation)" \
    "app/api/proxy.ts" \
    'x-base-url'

bold ""
bold "  9. SSRF via stream_fetch — Rust command with no URL validation"
check_absent \
    "stream.rs has no URL validation (no localhost/metadata check)" \
    "src-tauri/src/stream.rs" \
    'localhost|127\.0\.0\.1|169\.254|metadata|validate.*url|block.*url'

bold ""
bold "  10. XSS sink — dangerouslySetInnerHTML on plugin content"
check \
    "plugin.tsx renders plugin.content as raw HTML" \
    "app/components/plugin.tsx" \
    'dangerouslySetInnerHTML.*editingPlugin\.content'

bold ""
bold "  ──────────────────────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
    red   "  RESULT: ALL $PASS/$PASS CONDITIONS MET"
    red   "  → SERVER-SIDE RCE VIA addMcpServer IS EXPLOITABLE"
    red   "  → Any user with the shared access code can execute"
    red   "    arbitrary commands on the server."
else
    yellow "  RESULT: $FAIL of $((PASS + FAIL)) conditions not met"
    yellow "  Some vectors may be patched. Check details above."
fi
bold "  ──────────────────────────────────────────────────"
bold ""
bold "  Attack chain:"
bold "    HTTP POST → addMcpServer(id, {command: X, args: Y}, CODE)"
bold "    → initializeSingleClient() → createClient()"
bold "    → StdioClientTransport({command: X, args: Y})"
bold "    → child_process.spawn(X, Y)"
bold "    → FULL RCE"
bold ""
