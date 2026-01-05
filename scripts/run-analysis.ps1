# Main execution script for doc-freshness-analyzer
# Collects docs, reality, and source code for deep Claude analysis

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Target,
    
    [Parameter(Position=1)]
    [string]$Owner,
    
    [Parameter(Position=2)]
    [string]$Branch,
    
    [string]$OutputDir = "",
    [switch]$JsonOnly,
    [switch]$IncludeSource,
    [switch]$Incremental,
    [switch]$VerifyUrls,
    [switch]$InvalidateCache,
    [switch]$DeepMode,
    [int]$MaxSourceFiles = 15,
    [int]$RecentDays = 30
)

# Set defaults if not provided
if (-not $Owner -or $Owner -eq "" -or $Owner.Length -lt 3) { $Owner = "tenormusica2024" }
if (-not $Branch -or $Branch -eq "") { $Branch = "main" }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startTime = Get-Date

# Clear GITHUB_TOKEN to use gh auth
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

# Handle cache invalidation
if ($InvalidateCache) {
    $cacheScript = Join-Path $ScriptDir "cache-manager.ps1"
    & $cacheScript -Action invalidate -Target $Target -Owner $Owner
    Write-Host "Cache invalidated for $Target" -ForegroundColor Yellow
    if (-not $Incremental -and -not $JsonOnly) {
        return
    }
}

# Incremental mode: check for changed files
$incrementalData = $null
$changedFiles = @()
$isIncremental = $false

if ($Incremental) {
    $cacheScript = Join-Path $ScriptDir "cache-manager.ps1"
    if (Test-Path $cacheScript) {
        Write-Host "[INCREMENTAL] Checking for changes since last analysis..." -ForegroundColor Cyan
        $diffResult = & $cacheScript -Action diff -Target $Target -Owner $Owner -Branch $Branch | Out-String | ConvertFrom-Json
        
        if ($diffResult.success -and $diffResult.noChanges) {
            Write-Host "[INCREMENTAL] No changes detected. Using cached results." -ForegroundColor Green
            $cacheResult = & $cacheScript -Action load -Target $Target -Owner $Owner | Out-String | ConvertFrom-Json
            if ($cacheResult.exists -and $cacheResult.cache.data) {
                if ($JsonOnly) {
                    $cacheResult.cache.data | ConvertTo-Json -Depth 10
                } else {
                    Write-Host "Cached analysis from: $($cacheResult.cache.timestamp)" -ForegroundColor Gray
                    Write-Host $cacheResult.cache.data.context
                }
                return $cacheResult.cache.data
            }
        } elseif ($diffResult.success) {
            $changedFiles = $diffResult.changedFiles
            $isIncremental = $true
            Write-Host "[INCREMENTAL] $($changedFiles.Count) file(s) changed since last analysis" -ForegroundColor Yellow
            foreach ($f in $changedFiles | Select-Object -First 10) {
                Write-Host "  - $f" -ForegroundColor Gray
            }
            if ($changedFiles.Count -gt 10) {
                Write-Host "  ... and $($changedFiles.Count - 10) more" -ForegroundColor Gray
            }
        } else {
            Write-Host "[INCREMENTAL] $($diffResult.reason) - Running full analysis" -ForegroundColor Yellow
        }
    }
}

Write-Host "=== Document Freshness Analyzer (Deep Analysis) ===" -ForegroundColor Cyan
Write-Host "Target: $Target" -ForegroundColor Gray
Write-Host "Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host ""

# Phase 1: Collect Documents
Write-Host "[1/4] Collecting documentation..." -ForegroundColor Yellow
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
Write-Host "[2/4] Collecting code reality..." -ForegroundColor Yellow
try {
    $realityJson = & "$ScriptDir\collect-reality.ps1" -Target $Target -Owner $Owner -Branch $Branch
    $reality = $realityJson | Out-String | ConvertFrom-Json
    Write-Host "  Found $($reality.summary.totalFiles) files, runtime: $($reality.summary.runtime)" -ForegroundColor Green
}
catch {
    Write-Host "  Error collecting reality: $_" -ForegroundColor Red
    $reality = @{ fileStructure = @(); errors = @($_) }
}

# Phase 3: Collect Source Code (smart mode by default, deep mode optional)
$modeLabel = if ($DeepMode) { "ALL source files (DeepMode)" } else { "active source files (SmartMode)" }
Write-Host "[3/4] Collecting $modeLabel..." -ForegroundColor Yellow
$sourceData = $null
try {
    $sourceScript = Join-Path $ScriptDir "collect-source.ps1"
    if (Test-Path $sourceScript) {
        $sourceArgs = @{
            Target = $Target
            Owner = $Owner
            Branch = $Branch
            RecentDays = $RecentDays
        }
        if ($DeepMode) { $sourceArgs.DeepMode = $true }
        if ($reality) { $sourceArgs.RealityData = $reality }
        
        $sourceJson = & $sourceScript @sourceArgs
        $sourceData = $sourceJson | Out-String | ConvertFrom-Json
        
        Write-Host "  Total files in repo: $($sourceData.summary.totalFilesInRepo)" -ForegroundColor Green
        Write-Host "  Mode: $($sourceData.summary.mode) | Active: $($sourceData.summary.activeFileCount) | Inactive: $($sourceData.summary.inactiveFileCount)" -ForegroundColor Cyan
        Write-Host "  Source files with content: $($sourceData.summary.totalSourceFiles) ($($sourceData.summary.totalLines) lines)" -ForegroundColor Green
        Write-Host "  Exports: $($sourceData.summary.totalExports) | Imports: $($sourceData.summary.totalImports) | Routes: $($sourceData.summary.totalRoutes)" -ForegroundColor Green
        if ($sourceData.summary.legacyFileCount -gt 0) {
            Write-Host "  Legacy/backup files detected: $($sourceData.summary.legacyFileCount)" -ForegroundColor Yellow
        }
        if ($sourceData.summary.potentiallyUnusedCount -gt 0) {
            Write-Host "  Potentially unused files: $($sourceData.summary.potentiallyUnusedCount)" -ForegroundColor Yellow
        }
        if ($sourceData.inactiveFiles -and $sourceData.inactiveFiles.Count -gt 0) {
            Write-Host "  Inactive files (content skipped): $($sourceData.inactiveFiles.Count)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  Source collection script not found, skipping..." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Error collecting source: $_" -ForegroundColor Red
    $sourceData = @{ sourceFiles = @(); exports = @(); routes = @(); imports = @(); legacyFiles = @(); potentiallyUnused = @(); errors = @($_) }
}

# Phase 4: Prepare analysis data
Write-Host "[4/4] Preparing deep analysis context..." -ForegroundColor Yellow

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

$analysisData = @{
    target = $Target
    source = if ($docs.source) { $docs.source } else { $Target }
    timestamp = $startTime.ToString("yyyy-MM-dd HH:mm:ss")
    collectionDuration = "$([math]::Round($duration, 1)) seconds"
    documents = $docs
    reality = $reality
    sourceCode = $sourceData
}

# Output JSON for Claude analysis
if ($JsonOnly) {
    $analysisData | ConvertTo-Json -Depth 10
    return
}

# Read the analysis prompt template
$promptTemplate = Get-Content -Path "$ScriptDir\analyze-prompt.md" -Raw -ErrorAction SilentlyContinue

# Generate comprehensive analysis context for Claude
$analysisContext = @"
# Document Freshness Deep Analysis Request

## Target Repository
- **Name**: $($analysisData.source)
- **Analyzed at**: $($analysisData.timestamp)
- **Data Collection Time**: $($analysisData.collectionDuration)

---

## PART 1: Documentation ($($docs.summary.totalFiles) files, $($docs.summary.totalLines) lines)

"@

foreach ($doc in $docs.documents) {
    $analysisContext += @"

### Document: $($doc.path)
**Size**: $($doc.lines) lines, $($doc.size) bytes

``````markdown
$($doc.content)
``````

"@
}

$analysisContext += @"

---

## PART 2: Code Reality

### 2.1 File Structure ($($reality.summary.totalFiles) files)
``````
$($reality.fileStructure -join "`n")
``````

### 2.2 Dependencies
``````json
$($reality.dependencies | ConvertTo-Json -Depth 3)
``````

### 2.3 NPM Scripts
``````json
$($reality.scripts | ConvertTo-Json -Depth 3)
``````

### 2.4 Config Files
$($reality.configFiles -join "`n")

"@

# Add source code analysis if available
if ($sourceData -and $sourceData.sourceFiles.Count -gt 0) {
    $analysisContext += @"

---

## PART 3: Source Code Analysis

### 3.1 File Categories Summary
``````json
$($sourceData.summary.categorySummary | ConvertTo-Json -Depth 3)
``````

### 3.2 Exported Functions/Classes ($($sourceData.summary.totalExports) exports)
``````json
$($sourceData.exports | ConvertTo-Json -Depth 3)
``````

### 3.3 Import Graph ($($sourceData.summary.totalImports) imports)
``````json
$($sourceData.imports | ConvertTo-Json -Depth 3)
``````

### 3.4 API Routes ($($sourceData.summary.totalRoutes) routes)
``````json
$($sourceData.routes | ConvertTo-Json -Depth 3)
``````

### 3.5 External URLs ($($sourceData.summary.totalExternalUrls) URLs)
``````json
$($sourceData.externalUrls | ConvertTo-Json -Depth 3)
``````

### 3.6 Legacy/Backup Files Detected ($($sourceData.summary.legacyFileCount) files)
``````json
$($sourceData.legacyFiles | ConvertTo-Json -Depth 3)
``````

### 3.7 Potentially Unused Files ($($sourceData.summary.potentiallyUnusedCount) files)
These files have exports but are not imported anywhere, or have no exports at all:
``````json
$($sourceData.potentiallyUnused | ConvertTo-Json -Depth 3)
``````

### 3.8 All Source Files ($($sourceData.summary.totalSourceFiles) files, $($sourceData.summary.totalLines) lines)

"@

    foreach ($src in $sourceData.sourceFiles) {
        $analysisContext += @"

#### $($src.path)
**Category**: $($src.category) | **Lines**: $($src.lines) | **Size**: $($src.size) bytes

``````javascript
$($src.content)
``````

"@
    }
}

$analysisContext += @"

---

## PART 4: Deep Analysis Instructions

**IMPORTANT**: This analysis should take **5-10 minutes minimum**. If you complete in under 3 minutes, you have not been thorough enough.

### Phase A: Claim Extraction (2-3 minutes)
1. Go through EVERY line of documentation
2. Extract ALL technical claims:
   - File paths (even partial like `src/` or `./config`)
   - Commands (npm install, npm run dev, etc.)
   - Package names mentioned
   - Version numbers
   - Environment variables
   - Function/class names
   - URLs
   - Configuration examples
3. Create a numbered list of extracted claims

### Phase B: Deep Verification (3-5 minutes)
For EACH extracted claim:

**File Path Verification:**
- Does the exact path exist in fileStructure?
- Case sensitivity check
- Check for typos (util vs utils)
- Check file extensions (.js vs .ts)

**Command Verification:**
- Package manager consistency (npm vs bun vs yarn)
- Script existence in package.json scripts
- Working directory assumptions

**Dependency Verification:**
- Mentioned but not in package.json?
- In package.json but not documented?
- Dev vs production dependency confusion?

**Code Example Verification:**
- Do import paths resolve? (Check against Import Graph)
- Do function signatures match actual exports? (Check against Exports list)
- Are shown parameters correct?

**API/Route Verification:**
- Do documented endpoints match actual routes? (Check against Routes list)
- HTTP methods correct?
- Response formats accurate?

**Unused/Legacy File Detection:**
- Review the "Potentially Unused Files" list - should these be removed?
- Review the "Legacy/Backup Files" list - should these be cleaned up?
- Are any unused files mentioned in documentation but no longer needed?

**Import/Export Consistency:**
- Are there exports that nothing imports? (dead code)
- Are there imports that reference non-existent files?
- Circular dependency detection

### Phase C: Semantic Analysis (1-2 minutes)
- Contradiction detection (docs say X in one place, Y in another)
- Completeness check (what's missing for new users?)
- Outdated reference detection (removed features still documented?)

### Phase D: Impact Assessment (1 minute)
For each issue:
- **P0 (Critical)**: Blocks new user onboarding
- **P1 (High)**: Causes runtime errors
- **P2 (Medium)**: Causes confusion
- **P3 (Low)**: Minor inconsistency

---

## Required Output Format

Provide your analysis as a detailed JSON object:

``````json
{
  "analysisMetadata": {
    "analysisStartTime": "ISO timestamp",
    "analysisEndTime": "ISO timestamp",
    "totalClaimsExtracted": 0,
    "totalClaimsVerified": 0
  },
  "summary": {
    "freshnessScore": "0-100",
    "totalIssues": 0,
    "critical": 0,
    "warning": 0,
    "info": 0,
    "overallAssessment": "1-2 sentence summary"
  },
  "extractedClaims": [
    {
      "id": 1,
      "type": "FILE_PATH|COMMAND|DEPENDENCY|ENV_VAR|FUNCTION|URL|CONFIG",
      "claim": "exact text",
      "location": "README.md:45",
      "verified": true,
      "verificationNote": "how verified"
    }
  ],
  "issues": [
    {
      "id": "ISSUE-001",
      "severity": "critical|warning|info",
      "priority": "P0|P1|P2|P3",
      "category": "FILE_NOT_FOUND|COMMAND_INVALID|DEPENDENCY_MISSING|...",
      "location": {
        "file": "README.md",
        "lineNumber": 45,
        "lineContent": "exact line"
      },
      "documentSays": "what docs claim",
      "realityIs": "actual state",
      "userImpact": "how this affects users",
      "suggestedFix": "copy-paste ready fix"
    }
  ],
  "verified": [
    {
      "claim": "what was verified correct",
      "location": "file:line"
    }
  ],
  "missingDocumentation": [
    {
      "topic": "what should be documented",
      "reason": "why important"
    }
  ],
  "recommendations": {
    "immediateActions": ["P0/P1 fixes"],
    "shortTermActions": ["P2 fixes"],
    "longTermActions": ["P3 fixes"]
  }
}
``````

---

**BEGIN DEEP ANALYSIS NOW. Take your time. Be thorough.**

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

# URL Verification (optional)
$urlVerificationResults = $null
if ($VerifyUrls -and $sourceData -and $sourceData.externalUrls.Count -gt 0) {
    Write-Host ""
    Write-Host "[URL CHECK] Verifying $($sourceData.externalUrls.Count) external URLs..." -ForegroundColor Yellow
    $verifyScript = Join-Path $ScriptDir "verify-urls.ps1"
    if (Test-Path $verifyScript) {
        $urlVerificationResults = & $verifyScript -UrlData $sourceData.externalUrls -TimeoutSeconds 10 -DelayMs 500 | Out-String | ConvertFrom-Json
        if ($urlVerificationResults.deadLinks.Count -gt 0) {
            Write-Host "[URL CHECK] Found $($urlVerificationResults.deadLinks.Count) dead link(s)!" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Data Collection Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Duration: $([math]::Round($duration, 1)) seconds" -ForegroundColor Gray
if ($isIncremental) {
    Write-Host "Mode: Incremental ($($changedFiles.Count) changed files)" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "NOTE: The actual analysis by Claude should take 5-10 minutes for thorough verification." -ForegroundColor Yellow

$resultData = @{
    context = $analysisContext
    documents = $docs
    reality = $reality
    sourceCode = $sourceData
    urlVerification = $urlVerificationResults
    collectionDuration = $duration
    incremental = $isIncremental
    changedFiles = $changedFiles
}

# Save to cache for incremental mode
if (-not $JsonOnly) {
    $cacheScript = Join-Path $ScriptDir "cache-manager.ps1"
    if (Test-Path $cacheScript) {
        $saveResult = & $cacheScript -Action save -Target $Target -Owner $Owner -Branch $Branch -Data $resultData | Out-String | ConvertFrom-Json
        if ($saveResult.success) {
            $shortHash = if ($saveResult.commitHash -and $saveResult.commitHash.Length -ge 7) { 
                $saveResult.commitHash.Substring(0, 7) 
            } else { 
                "(no commit)" 
            }
            Write-Host "Results cached at commit: $shortHash" -ForegroundColor Gray
        }
    }
}

return $resultData
