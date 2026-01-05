# doc-freshness-analyzer installer
# Installs the tool and slash command globally

param(
    [switch]$Uninstall,
    [string]$InstallPath = "$env:USERPROFILE\doc-freshness-analyzer-temp"
)

$ErrorActionPreference = "Stop"

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$globalCommandsDir = "$env:USERPROFILE\.claude\commands"

Write-Host "=== doc-freshness-analyzer Installer ===" -ForegroundColor Cyan
Write-Host ""

if ($Uninstall) {
    Write-Host "Uninstalling..." -ForegroundColor Yellow
    
    # Remove global slash command
    $globalCommand = "$globalCommandsDir\doc-freshness.md"
    if (Test-Path $globalCommand) {
        Remove-Item $globalCommand -Force
        Write-Host "  Removed: $globalCommand" -ForegroundColor Green
    }
    
    # Remove installed directory
    if (Test-Path $InstallPath) {
        Remove-Item $InstallPath -Recurse -Force
        Write-Host "  Removed: $InstallPath" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Uninstall complete!" -ForegroundColor Green
    return
}

# Install
Write-Host "Installing to: $InstallPath" -ForegroundColor Gray
Write-Host ""

# 1. Copy tool files
if ($sourceDir -ne $InstallPath) {
    Write-Host "[1/3] Copying tool files..." -ForegroundColor Yellow
    
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    }
    
    # Copy scripts
    $scriptsDir = "$InstallPath\scripts"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }
    
    Copy-Item "$sourceDir\scripts\*" -Destination $scriptsDir -Force -Recurse
    Write-Host "  Copied scripts to: $scriptsDir" -ForegroundColor Green
} else {
    Write-Host "[1/3] Running from install location, skipping copy" -ForegroundColor Gray
}

# 2. Install global slash command
Write-Host "[2/3] Installing global slash command..." -ForegroundColor Yellow

if (-not (Test-Path $globalCommandsDir)) {
    New-Item -ItemType Directory -Path $globalCommandsDir -Force | Out-Null
}

$commandSource = "$sourceDir\.claude\commands\doc-freshness.md"
$commandDest = "$globalCommandsDir\doc-freshness.md"

if (Test-Path $commandSource) {
    Copy-Item $commandSource -Destination $commandDest -Force
    Write-Host "  Installed: /doc-freshness" -ForegroundColor Green
} else {
    Write-Host "  Warning: Command file not found at $commandSource" -ForegroundColor Yellow
}

# 3. Verify installation
Write-Host "[3/3] Verifying installation..." -ForegroundColor Yellow

$checks = @(
    @{ Path = "$InstallPath\scripts\run-analysis.ps1"; Name = "run-analysis.ps1" }
    @{ Path = "$InstallPath\scripts\collect-source.ps1"; Name = "collect-source.ps1" }
    @{ Path = "$globalCommandsDir\doc-freshness.md"; Name = "/doc-freshness command" }
)

$allOk = $true
foreach ($check in $checks) {
    if (Test-Path $check.Path) {
        Write-Host "  OK: $($check.Name)" -ForegroundColor Green
    } else {
        Write-Host "  Missing: $($check.Name)" -ForegroundColor Red
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) {
    Write-Host "Installation complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  In Claude Code: /doc-freshness owner/repo" -ForegroundColor Gray
    Write-Host "  Direct:         $InstallPath\scripts\run-analysis.ps1 -Target owner/repo" -ForegroundColor Gray
} else {
    Write-Host "Installation completed with warnings." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To uninstall: .\install.ps1 -Uninstall" -ForegroundColor Gray
