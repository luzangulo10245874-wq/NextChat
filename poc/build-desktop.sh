#!/usr/bin/env bash
# Build NextChat Desktop (Tauri) for PoC testing.
#
# Fixes the "Server Actions are not supported with static export" error
# by swapping app/mcp/actions.ts with a no-op stub during the build.
#
# Usage:
#   bash poc/build-desktop.sh          # Build for current platform
#   bash poc/build-desktop.sh --dev    # Dev mode (hot reload)
#
# On Windows, run from Git Bash or WSL.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTIONS="$REPO_ROOT/app/mcp/actions.ts"
STUB="$REPO_ROOT/app/mcp/actions-stub.ts"
BACKUP="$REPO_ROOT/app/mcp/actions.ts.server-bak"

cleanup() {
    if [ -f "$BACKUP" ]; then
        echo "[*] Restoring original actions.ts ..."
        mv "$BACKUP" "$ACTIONS"
    fi
}
trap cleanup EXIT

if [ ! -f "$STUB" ]; then
    echo "[!] Stub file not found: $STUB"
    echo "    Run this script from the repo root."
    exit 1
fi

echo "[*] Swapping actions.ts with stub for static export ..."
cp "$ACTIONS" "$BACKUP"
cp "$STUB" "$ACTIONS"

cd "$REPO_ROOT"

if [ "${1:-}" = "--dev" ]; then
    echo "[*] Starting Tauri dev mode ..."
    yarn app:dev
else
    echo "[*] Building Tauri desktop app ..."
    yarn app:build
    echo ""
    echo "[+] Build complete!"
    echo "    Binary: src-tauri/target/release/NextChat$([ "$(uname -s)" = "MINGW"* ] && echo '.exe' || true)"
    echo "    Installer: src-tauri/target/release/bundle/"
fi
