# Main execution script for doc-freshness-analyzer
# Collects docs and reality, then outputs data for Claude analysis

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Target,
    
    [Parameter(Position=1)]
    [string]$Owner,
    
    [Parameter(Position=2)]
    [string]$Branch,
    
    [string]$OutputDir = "",
    [switch]$JsonOnly
)

# Set defaults if not provided
if (-not $Owner -or $Owner -eq "" -or $Owner.Length -lt 3) { $Owner = "tenormusica2024" }
if (-not $Branch -or $Branch -eq "") { $Branch = "main" }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Clear GITHUB_TOKEN to use gh auth
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

Write-Host "=== Document Freshness Analyzer ===" -ForegroundColor Cyan
Write-Host "Target: $Target" -ForegroundColor Gray
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Phase 1: Collect Documents
Write-Host "[1/3] Collecting documentation..." -ForegroundColor Yellow
try {
    $docsScript = Join-Path $ScriptDir "collect-docs.ps1"
    $docsJson = & $docsScript -Target $Target -Owner $Owner -Branch $Branch
    $docs = $docsJson | Out-String | ConvertFrom-Json
    Write-Host "  Found $($docs.summary.totalFiles) document(s), $($docs.summary.totalLines) lines" -ForegroundColor Green
}
catch {
    Write-Host "  Error collecting docs: $_" -ForegroundColor Red
    $docs = @{ documents = @(); errors = @($_); summary = @{ totalFiles = 0 } }
}

# Phase 2: Collect Code Reality
Write-Host "[2/3] Collecting code reality..." -ForegroundColor Yellow
try {
    $realityJson = & "$ScriptDir\collect-reality.ps1" -Target $Target -Owner $Owner -Branch $Branch
    $reality = $realityJson | ConvertFrom-Json
    Write-Host "  Found $($reality.summary.totalFiles) files, runtime: $($reality.summary.runtime)" -ForegroundColor Green
}
catch {
    Write-Host "  Error collecting reality: $_" -ForegroundColor Red
    $reality = @{ fileStructure = @(); errors = @($_) }
}

# Phase 3: Prepare analysis data
Write-Host "[3/3] Preparing analysis data..." -ForegroundColor Yellow

$analysisData = @{
    target = $Target
    source = if ($docs.source) { $docs.source } else { $Target }
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    documents = $docs
    reality = $reality
}

# Output JSON for Claude analysis
if ($JsonOnly) {
    $analysisData | ConvertTo-Json -Depth 10
    return
}

# Generate analysis context for Claude
$analysisContext = @"
# Document Freshness Analysis Request

## Target Repository
- **Name**: $($analysisData.source)
- **Analyzed at**: $($analysisData.timestamp)

## Documents Found ($($docs.summary.totalFiles) files)

"@

foreach ($doc in $docs.documents) {
    $analysisContext += @"

### $($doc.path)
``````markdown
$($doc.content)
``````

"@
}

$analysisContext += @"

## Code Reality

### File Structure ($($reality.summary.totalFiles) files)
``````
$($reality.fileStructure -join "`n")
``````

### Dependencies
``````json
$($reality.dependencies | ConvertTo-Json -Depth 3)
``````

### Scripts (package.json)
``````json
$($reality.scripts | ConvertTo-Json -Depth 3)
``````

### Config Files
$($reality.configFiles -join "`n")

---

## Analysis Instructions

Please analyze the documentation against the code reality and identify:

1. **File paths** mentioned in docs that don't exist
2. **Commands** that won't work (wrong package manager, missing scripts)
3. **Dependencies** mentioned but not installed
4. **Version mismatches** 
5. **Environment variables** that don't match .env.example
6. **Any other discrepancies**

For each issue, provide:
- Severity (Critical/Warning/Info)
- Location (file and line if possible)
- What the doc says vs reality
- Suggested fix

"@

# Save or output
if ($OutputDir) {
    $outputPath = Join-Path $OutputDir "analysis-context-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
    $analysisContext | Out-File -FilePath $outputPath -Encoding UTF8
    Write-Host ""
    Write-Host "Analysis context saved to: $outputPath" -ForegroundColor Green
    Write-Host "Feed this to Claude for detailed analysis." -ForegroundColor Gray
}
else {
    Write-Host ""
    Write-Host "=== Analysis Context ===" -ForegroundColor Cyan
    Write-Host $analysisContext
}

Write-Host ""
Write-Host "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

return @{
    context = $analysisContext
    documents = $docs
    reality = $reality
}
