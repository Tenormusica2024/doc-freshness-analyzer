# Debug collect-docs
$Target = "neon-charts"
$Owner = "tenormusica2024"
$Branch = "main"

Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

Write-Host "=== Testing collect-docs logic ===" -ForegroundColor Cyan

# Get repository tree
$apiPath = "repos/$Owner/$Target/git/trees/${Branch}?recursive=1"
Write-Host "API Path: $apiPath"

$treeJson = & 'C:/Program Files/GitHub CLI/gh.exe' api $apiPath 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error getting tree: $treeJson" -ForegroundColor Red
    exit 1
}

$tree = $treeJson | ConvertFrom-Json
Write-Host "Tree items: $($tree.tree.Count)"

# Filter markdown files
$mdFiles = $tree.tree | Where-Object { 
    $_.path -match "\.md$" -and 
    $_.path -notmatch "node_modules|vendor|dist|build" -and
    $_.type -eq "blob"
}

Write-Host "Markdown files: $($mdFiles.Count)"

$documents = @()
foreach ($file in $mdFiles) {
    Write-Host "  Fetching: $($file.path)" -ForegroundColor Yellow
    try {
        $contentPath = "repos/$Owner/$Target/contents/$($file.path)?ref=$Branch"
        $contentJson = & 'C:/Program Files/GitHub CLI/gh.exe' api $contentPath 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    Error: $contentJson" -ForegroundColor Red
            continue
        }
        
        $contentData = $contentJson | ConvertFrom-Json
        
        if ($contentData.encoding -eq "base64") {
            $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($contentData.content))
            Write-Host "    OK: $($content.Length) bytes" -ForegroundColor Green
            
            $documents += @{
                path = $file.path
                lines = ($content -split "`n").Count
                size = $contentData.size
            }
        }
    }
    catch {
        Write-Host "    Exception: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Total documents: $($documents.Count)" -ForegroundColor Cyan
