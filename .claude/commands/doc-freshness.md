# /doc-freshness - Document Freshness Analyzer

Analyze documentation freshness for a GitHub repository or local directory.

## Usage

```
/doc-freshness <target> [options]
```

## Arguments

- `target`: GitHub repository (owner/repo) or local path

## Options

- `--deep`: DeepMode - analyze all source files (default: SmartMode)
- `--incremental`: Only analyze changed files since last run
- `--verify-urls`: Check external URLs for dead links

## Examples

```
/doc-freshness ai-trend-daily
/doc-freshness Tenormusica2024/portfolio --deep
/doc-freshness C:\Projects\my-app --incremental
/doc-freshness owner/repo --verify-urls
```

## What it does

1. Collects documentation (README.md, docs/)
2. Collects code reality (file structure, dependencies, exports/imports)
3. Compares documentation claims against actual code
4. Reports mismatches with suggested fixes

## Output

- **Issues**: Verified problems (FILE_NOT_FOUND, VERSION_MISMATCH, etc.)
- **Potential Issues**: Needs manual verification
- **Freshness Score**: 0-100 quality rating

## Implementation

$ARGUMENTS

```powershell
# Validate and sanitize arguments (P0: security)
$rawArgs = "$ARGUMENTS"
if ([string]::IsNullOrWhiteSpace($rawArgs)) {
    Write-Host "Error: No target specified" -ForegroundColor Red
    Write-Host "Usage: /doc-freshness <target> [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  /doc-freshness owner/repo" -ForegroundColor Gray
    Write-Host "  /doc-freshness owner/repo --deep" -ForegroundColor Gray
    Write-Host "  /doc-freshness C:\Projects\my-app --incremental" -ForegroundColor Gray
    return
}

# Sanitize: remove dangerous shell characters (P2: extended pattern)
$sanitizedArgs = $rawArgs -replace '[;&|<>`$(){}[\]]', ''
$argArray = $sanitizedArgs -split '\s+' | Where-Object { $_ -ne '' }

$target = $argArray[0]
$options = if ($argArray.Count -gt 1) { $argArray[1..($argArray.Count-1)] } else { @() }

# Cross-platform script directory detection (P1: compatibility)
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$scriptDir = Join-Path $homeDir "doc-freshness-analyzer-temp" "scripts"

if (-not (Test-Path $scriptDir)) {
    # Fallback to current directory
    $scriptDir = Join-Path (Get-Location).Path "scripts"
}

if (-not (Test-Path $scriptDir)) {
    Write-Host "Error: Script directory not found" -ForegroundColor Red
    Write-Host "Expected locations:" -ForegroundColor Yellow
    Write-Host "  - $homeDir\doc-freshness-analyzer-temp\scripts" -ForegroundColor Gray
    Write-Host "  - $(Get-Location)\scripts" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Please run install.ps1 or navigate to the doc-freshness-analyzer directory" -ForegroundColor Cyan
    return
}

# Build parameters
$params = @{
    Target = $target
}

if ($options -contains "--deep") { $params.DeepMode = $true }
if ($options -contains "--incremental") { $params.Incremental = $true }
if ($options -contains "--verify-urls") { $params.VerifyUrls = $true }

Write-Host "Analyzing: $target" -ForegroundColor Cyan
Write-Host "Script directory: $scriptDir" -ForegroundColor Gray
Write-Host ""

& (Join-Path $scriptDir "run-analysis.ps1") @params
```

After running the script, analyze the output context and provide:
1. Summary of issues found (grouped by severity)
2. Top 3 priority fixes with copy-paste solutions
3. Overall freshness assessment
