# doc-freshness-analyzer installer
# Installs the tool and slash command globally

param(
    [switch]$Uninstall,
    [switch]$Force,
    [string]$InstallPath
)

$ErrorActionPreference = "Stop"

# Cross-platform home directory detection (P1: compatibility)
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
if (-not $InstallPath) {
    $InstallPath = Join-Path $homeDir "doc-freshness-analyzer-temp"
}

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$globalCommandsDir = Join-Path $homeDir ".claude" "commands"

Write-Host "=== doc-freshness-analyzer Installer ===" -ForegroundColor Cyan
Write-Host ""

if ($Uninstall) {
    # Uninstall confirmation (P1: safety)
    if (-not $Force) {
        Write-Host "This will remove:" -ForegroundColor Yellow
        Write-Host "  - $InstallPath" -ForegroundColor Gray
        Write-Host "  - $(Join-Path $globalCommandsDir 'doc-freshness.md')" -ForegroundColor Gray
        Write-Host ""
        $confirmation = Read-Host "Are you sure? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-Host "Uninstall cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    Write-Host "Uninstalling..." -ForegroundColor Yellow
    
    # Remove global slash command
    $globalCommand = Join-Path $globalCommandsDir "doc-freshness.md"
    if (Test-Path $globalCommand) {
        Remove-Item $globalCommand -Force
        Write-Host "  Removed: $globalCommand" -ForegroundColor Green
    } else {
        Write-Host "  Not found: $globalCommand" -ForegroundColor Gray
    }
    
    # Remove installed directory
    if (Test-Path $InstallPath) {
        Remove-Item $InstallPath -Recurse -Force
        Write-Host "  Removed: $InstallPath" -ForegroundColor Green
    } else {
        Write-Host "  Not found: $InstallPath" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Uninstall complete!" -ForegroundColor Green
    return
}

# Install
Write-Host "Installing to: $InstallPath" -ForegroundColor Gray
Write-Host ""

# 1. Copy tool files (P0: explicit file handling)
if ($sourceDir -ne $InstallPath) {
    Write-Host "[1/3] Copying tool files..." -ForegroundColor Yellow
    
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    }
    
    # Copy scripts directory
    $scriptsSource = Join-Path $sourceDir "scripts"
    $scriptsDir = Join-Path $InstallPath "scripts"
    
    if (Test-Path $scriptsSource) {
        if (-not (Test-Path $scriptsDir)) {
            New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
        }
        
        # Explicit file copy (P0: security - no wildcard ambiguity)
        Get-ChildItem $scriptsSource -File | ForEach-Object {
            Copy-Item $_.FullName -Destination $scriptsDir -Force
        }
        Write-Host "  Copied scripts to: $scriptsDir" -ForegroundColor Green
    } else {
        Write-Host "  Error: Scripts directory not found at $scriptsSource" -ForegroundColor Red
        Write-Host "  Please ensure you're running from the repository root" -ForegroundColor Yellow
        return
    }
} else {
    Write-Host "[1/3] Running from install location, skipping copy" -ForegroundColor Gray
}

# 2. Install global slash command
Write-Host "[2/3] Installing global slash command..." -ForegroundColor Yellow

if (-not (Test-Path $globalCommandsDir)) {
    New-Item -ItemType Directory -Path $globalCommandsDir -Force | Out-Null
    Write-Host "  Created: $globalCommandsDir" -ForegroundColor Gray
}

$commandSource = Join-Path $sourceDir ".claude" "commands" "doc-freshness.md"
$commandDest = Join-Path $globalCommandsDir "doc-freshness.md"

if (Test-Path $commandSource) {
    Copy-Item $commandSource -Destination $commandDest -Force
    Write-Host "  Installed: /doc-freshness" -ForegroundColor Green
} else {
    Write-Host "  Warning: Command file not found at $commandSource" -ForegroundColor Yellow
    Write-Host "  The slash command will not be available globally" -ForegroundColor Yellow
    Write-Host "  You can still use it from the repository directory" -ForegroundColor Gray
}

# 3. Verify installation
Write-Host "[3/3] Verifying installation..." -ForegroundColor Yellow

$checks = @(
    @{ Path = (Join-Path $InstallPath "scripts" "run-analysis.ps1"); Name = "run-analysis.ps1" }
    @{ Path = (Join-Path $InstallPath "scripts" "collect-source.ps1"); Name = "collect-source.ps1" }
    @{ Path = $commandDest; Name = "/doc-freshness command" }
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
    Write-Host "  Direct:         $(Join-Path $InstallPath 'scripts' 'run-analysis.ps1') -Target owner/repo" -ForegroundColor Gray
} else {
    Write-Host "Installation completed with warnings." -ForegroundColor Yellow
    Write-Host "Some features may not work correctly." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To uninstall: .\install.ps1 -Uninstall" -ForegroundColor Gray
Write-Host "To force uninstall without confirmation: .\install.ps1 -Uninstall -Force" -ForegroundColor Gray
