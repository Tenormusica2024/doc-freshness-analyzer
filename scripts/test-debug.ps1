# Debug test script
param([string]$Target = "portfolio", [string]$Owner = "tenormusica2024")

Write-Host "=== DEBUG ===" -ForegroundColor Cyan
Write-Host "Target: $Target"
Write-Host "Owner: $Owner"
Write-Host "Combined: $Owner/$Target"

# Clear GITHUB_TOKEN
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

# Test API path
$apiPath = "repos/$Owner/$Target/git/trees/main?recursive=1"
Write-Host "API Path: $apiPath"

# Call gh
Write-Host "Calling gh api..."
$result = & 'C:/Program Files/GitHub CLI/gh.exe' api $apiPath 2>&1
if ($LASTEXITCODE -eq 0) {
    $tree = $result | ConvertFrom-Json
    Write-Host "Success! Found $($tree.tree.Count) items in tree"
    $mdFiles = $tree.tree | Where-Object { $_.path -match "\.md$" -and $_.type -eq "blob" }
    Write-Host "Markdown files: $($mdFiles.Count)"
} else {
    Write-Host "Error: $result" -ForegroundColor Red
}
