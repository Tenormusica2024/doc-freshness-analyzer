# Auto-fix PR Creator for doc-freshness-analyzer
# Creates a PR with fixes based on analysis results

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    
    [Parameter(Mandatory=$true)]
    [string]$AnalysisResult,
    
    [string]$Owner = "tenormusica2024",
    [string]$BaseBranch = "main",
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

Write-Host "=== Doc Freshness Auto-Fix PR Creator ===" -ForegroundColor Cyan
Write-Host "Target: $Target" -ForegroundColor Gray
Write-Host "Analysis: $AnalysisResult" -ForegroundColor Gray
Write-Host ""

# Load analysis result
if (-not (Test-Path $AnalysisResult)) {
    Write-Host "Error: Analysis result file not found: $AnalysisResult" -ForegroundColor Red
    exit 1
}

$analysis = Get-Content $AnalysisResult -Raw | ConvertFrom-Json
$issues = $analysis.issues | Where-Object { $_.suggestedFix -and $_.suggestedFix -ne "" }

if ($issues.Count -eq 0) {
    Write-Host "No auto-fixable issues found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($issues.Count) auto-fixable issue(s)" -ForegroundColor Green
Write-Host ""

# Clear GITHUB_TOKEN to use gh auth
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

# Create fix branch
$branchName = "docs/freshness-fix-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$repoPath = "$Owner/$Target"

if ($DryRun) {
    Write-Host "[DRY RUN] Would create branch: $branchName" -ForegroundColor Yellow
} else {
    Write-Host "Creating branch: $branchName" -ForegroundColor Yellow
}

# Group issues by file
$issuesByFile = @{}
foreach ($issue in $issues) {
    $file = $issue.location.file
    if (-not $issuesByFile.ContainsKey($file)) {
        $issuesByFile[$file] = @()
    }
    $issuesByFile[$file] += $issue
}

# Apply fixes to each file
$fixedFiles = @()
$fixSummary = @()

foreach ($file in $issuesByFile.Keys) {
    $fileIssues = $issuesByFile[$file]
    Write-Host "Processing: $file ($($fileIssues.Count) issues)" -ForegroundColor Cyan
    
    # Fetch current file content
    try {
        $contentJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$repoPath/contents/$file`?ref=$BaseBranch" 2>$null
        $contentData = $contentJson | ConvertFrom-Json
        $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($contentData.content))
        $sha = $contentData.sha
    }
    catch {
        Write-Host "  Warning: Could not fetch $file - $_" -ForegroundColor Yellow
        continue
    }
    
    $originalContent = $content
    $appliedFixes = @()
    
    # Apply each fix
    foreach ($issue in $fileIssues) {
        $category = $issue.category
        $docSays = $issue.documentSays
        $realityIs = $issue.realityIs
        $suggestedFix = $issue.suggestedFix
        $line = $issue.location.line
        
        Write-Host "  [$category] Line $line" -ForegroundColor Gray
        
        # Parse suggestedFix to extract old/new values
        $fixApplied = $false
        
        switch -Regex ($category) {
            "FILE_NOT_FOUND|FILE_MOVED|EXTENSION_MISMATCH" {
                # Extract path changes from suggestedFix
                if ($suggestedFix -match "Change [`'\`""]?([^`'\`""]+)[`'\`""]?\s+to\s+[`'\`""]?([^`'\`""]+)[`'\`""]?") {
                    $oldPath = $Matches[1].Trim()
                    $newPath = $Matches[2].Trim()
                    $newContent = $content -replace [regex]::Escape($oldPath), $newPath
                    if ($newContent -ne $content) {
                        $content = $newContent
                        $fixApplied = $true
                        $appliedFixes += "Changed `$oldPath` to `$newPath`"
                    }
                }
            }
            "COMMAND_INVALID|PACKAGE_MANAGER_WRONG" {
                # Extract command changes
                if ($suggestedFix -match "Change [`'\`""]?([^`'\`""]+)[`'\`""]?\s+to\s+[`'\`""]?([^`'\`""]+)[`'\`""]?") {
                    $oldCmd = $Matches[1].Trim()
                    $newCmd = $Matches[2].Trim()
                    $newContent = $content -replace [regex]::Escape($oldCmd), $newCmd
                    if ($newContent -ne $content) {
                        $content = $newContent
                        $fixApplied = $true
                        $appliedFixes += "Changed command `$oldCmd` to `$newCmd`"
                    }
                }
            }
            "VERSION_MISMATCH" {
                # Extract version changes
                if ($suggestedFix -match "Update from ['`""]?([^'`""]+)['`""]?\s+to\s+['`""]?([^'`""]+)['`""]?") {
                    $oldVer = $Matches[1].Trim()
                    $newVer = $Matches[2].Trim()
                    $newContent = $content -replace [regex]::Escape($oldVer), $newVer
                    if ($newContent -ne $content) {
                        $content = $newContent
                        $fixApplied = $true
                        $appliedFixes += "Updated version from `$oldVer` to `$newVer`"
                    }
                }
            }
            "DEAD_LINK" {
                # Extract URL changes
                if ($suggestedFix -match "Update URL from ['`""]?([^'`""]+)['`""]?\s+to\s+['`""]?([^'`""]+)['`""]?") {
                    $oldUrl = $Matches[1].Trim()
                    $newUrl = $Matches[2].Trim()
                    $newContent = $content -replace [regex]::Escape($oldUrl), $newUrl
                    if ($newContent -ne $content) {
                        $content = $newContent
                        $fixApplied = $true
                        $appliedFixes += "Updated URL from `$oldUrl` to `$newUrl`"
                    }
                }
            }
        }
        
        if (-not $fixApplied) {
            Write-Host "    Skipped: Could not parse suggestedFix" -ForegroundColor Yellow
        }
    }
    
    # If content changed, prepare to commit
    if ($content -ne $originalContent -and $appliedFixes.Count -gt 0) {
        $fixedFiles += @{
            path = $file
            content = $content
            sha = $sha
            fixes = $appliedFixes
        }
        $fixSummary += $appliedFixes
        Write-Host "  Applied $($appliedFixes.Count) fix(es)" -ForegroundColor Green
    }
}

if ($fixedFiles.Count -eq 0) {
    Write-Host ""
    Write-Host "No fixes could be applied automatically." -ForegroundColor Yellow
    Write-Host "Manual intervention required for the detected issues." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Total files to update: $($fixedFiles.Count)" -ForegroundColor Cyan
Write-Host "Total fixes: $($fixSummary.Count)" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] Would create PR with following changes:" -ForegroundColor Yellow
    foreach ($f in $fixedFiles) {
        Write-Host "  - $($f.path): $($f.fixes -join ', ')" -ForegroundColor Gray
    }
    exit 0
}

# Create branch and commit changes
Write-Host "Creating branch and committing changes..." -ForegroundColor Yellow

# Get base branch SHA
$baseShaJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$repoPath/git/refs/heads/$BaseBranch" 2>$null
$baseSha = ($baseShaJson | ConvertFrom-Json).object.sha

# Create new branch
$branchBody = @{
    ref = "refs/heads/$branchName"
    sha = $baseSha
} | ConvertTo-Json

try {
    $branchBody | & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$repoPath/git/refs" -X POST --input - 2>$null | Out-Null
    Write-Host "  Created branch: $branchName" -ForegroundColor Green
}
catch {
    Write-Host "  Error creating branch: $_" -ForegroundColor Red
    exit 1
}

# Commit each file
foreach ($f in $fixedFiles) {
    $commitBody = @{
        message = "docs: fix $($f.fixes.Count) issue(s) in $($f.path)"
        content = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($f.content))
        sha = $f.sha
        branch = $branchName
    } | ConvertTo-Json
    
    try {
        $commitBody | & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$repoPath/contents/$($f.path)" -X PUT --input - 2>$null | Out-Null
        Write-Host "  Committed: $($f.path)" -ForegroundColor Green
    }
    catch {
        Write-Host "  Error committing $($f.path): $_" -ForegroundColor Red
    }
}

# Create PR
Write-Host ""
Write-Host "Creating Pull Request..." -ForegroundColor Yellow

$prTitle = "docs: fix $($fixSummary.Count) documentation issues"
$prBody = @"
## Summary

This PR fixes $($fixSummary.Count) documentation issue(s) detected by doc-freshness-analyzer.

## Changes

$(foreach ($f in $fixedFiles) {
"### $($f.path)`n$(($f.fixes | ForEach-Object { "- $_" }) -join "`n")`n"
})

## Detection Categories

| Category | Count |
|----------|-------|
$(($issues | Group-Object -Property category | ForEach-Object { "| $($_.Name) | $($_.Count) |" }) -join "`n")

---
Generated by doc-freshness-analyzer
"@

try {
    $prResult = & 'C:/Program Files/GitHub CLI/gh.exe' pr create --repo $repoPath --base $BaseBranch --head $branchName --title $prTitle --body $prBody 2>&1
    Write-Host ""
    Write-Host "Pull Request created successfully!" -ForegroundColor Green
    Write-Host $prResult -ForegroundColor Cyan
}
catch {
    Write-Host "Error creating PR: $_" -ForegroundColor Red
    Write-Host "Branch '$branchName' has been created with changes." -ForegroundColor Yellow
    Write-Host "You can create the PR manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Auto-Fix Complete ===" -ForegroundColor Cyan
