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
$scriptDir = "$env:USERPROFILE\doc-freshness-analyzer-temp\scripts"
if (-not (Test-Path $scriptDir)) {
    $scriptDir = (Get-Location).Path + "\scripts"
}

$target = "$ARGUMENTS".Split()[0]
$options = "$ARGUMENTS".Split() | Select-Object -Skip 1

$params = @{
    Target = $target
}

if ($options -contains "--deep") { $params.DeepMode = $true }
if ($options -contains "--incremental") { $params.Incremental = $true }
if ($options -contains "--verify-urls") { $params.VerifyUrls = $true }

& "$scriptDir\run-analysis.ps1" @params
```

After running the script, analyze the output context and provide:
1. Summary of issues found (grouped by severity)
2. Top 3 priority fixes with copy-paste solutions
3. Overall freshness assessment
