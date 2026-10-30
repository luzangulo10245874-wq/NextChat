# Build NextChat Desktop (Tauri) for PoC testing — PowerShell version.
#
# Fixes the "Server Actions are not supported with static export" error
# by swapping app/mcp/actions.ts with a no-op stub during the build.
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File poc\build-desktop.ps1
#   powershell -ExecutionPolicy Bypass -File poc\build-desktop.ps1 -Dev

param(
    [switch]$Dev
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Actions = Join-Path $RepoRoot "app\mcp\actions.ts"
$Stub    = Join-Path $RepoRoot "app\mcp\actions-stub.ts"
$Backup  = Join-Path $RepoRoot "app\mcp\actions.ts.server-bak"

function Restore-Original {
    if (Test-Path $Backup) {
        Write-Host "[*] Restoring original actions.ts ..." -ForegroundColor Yellow
        Move-Item -Force $Backup $Actions
    }
}

if (-not (Test-Path $Stub)) {
    Write-Host "[!] Stub file not found: $Stub" -ForegroundColor Red
    exit 1
}

try {
    Write-Host "[*] Swapping actions.ts with stub for static export ..." -ForegroundColor Cyan
    Copy-Item $Actions $Backup
    Copy-Item $Stub $Actions

    Set-Location $RepoRoot

    if ($Dev) {
        Write-Host "[*] Starting Tauri dev mode ..." -ForegroundColor Cyan
        yarn app:dev
    } else {
        Write-Host "[*] Building Tauri desktop app ..." -ForegroundColor Cyan
        yarn app:build

        Write-Host ""
        Write-Host "[+] Build complete!" -ForegroundColor Green
        Write-Host "    Binary:    src-tauri\target\release\NextChat.exe"
        Write-Host "    Installer: src-tauri\target\release\bundle\msi\"
    }
} finally {
    Restore-Original
}
