# Collect documentation files from a repository
# Supports both local paths and GitHub repos

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,  # Local path or GitHub repo name
    
    [string]$Owner = "tenormusica2024",
    [string]$Branch = "main"
)

$results = @{
    source = ""
    type = ""
    documents = @()
    errors = @()
}

# Determine if target is local path or GitHub repo
# A path must contain \ or / and exist to be considered local
$isLocalPath = ($Target -match "[/\\]") -and (Test-Path $Target -ErrorAction SilentlyContinue)

if ($isLocalPath) {
    $results.type = "local"
    $results.source = $Target
    
    # Find all markdown files
    $mdFiles = Get-ChildItem -Path $Target -Recurse -Filter "*.md" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "node_modules|\.git|vendor|dist|build" }
    
    foreach ($file in $mdFiles) {
        $relativePath = $file.FullName.Replace("$Target\", "").Replace("\", "/")
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        
        if ($content) {
            $results.documents += @{
                path = $relativePath
                content = $content
                lines = ($content -split "`n").Count
                size = $file.Length
            }
        }
    }
}
else {
    # Treat as GitHub repo name
    $results.type = "github"
    $results.source = "$Owner/$Target"
    
    # Remove GITHUB_TOKEN to use gh auth
    Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
    
    # Get repository tree
    try {
        $apiPath = "repos/$Owner/$Target/git/trees/${Branch}?recursive=1"
        $treeJson = & 'C:/Program Files/GitHub CLI/gh.exe' api $apiPath 2>$null
        $tree = $treeJson | ConvertFrom-Json
        
        # Filter markdown files
        $mdFiles = $tree.tree | Where-Object { 
            $_.path -match "\.md$" -and 
            $_.path -notmatch "node_modules|vendor|dist|build" -and
            $_.type -eq "blob"
        }
        
        foreach ($file in $mdFiles) {
            try {
                # Get file content
                $contentJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/contents/$($file.path)?ref=$Branch" 2>$null
                $contentData = $contentJson | ConvertFrom-Json
                
                if ($contentData.encoding -eq "base64") {
                    $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($contentData.content))
                    
                    $results.documents += @{
                        path = $file.path
                        content = $content
                        lines = ($content -split "`n").Count
                        size = $contentData.size
                    }
                }
            }
            catch {
                $results.errors += "Failed to fetch: $($file.path) - $_"
            }
        }
    }
    catch {
        $results.errors += "Failed to access repository: $_"
    }
}

# Summary
$totalLines = 0
$totalSize = 0
foreach ($doc in $results.documents) {
    if ($doc.lines) { $totalLines += $doc.lines }
    if ($doc.size) { $totalSize += $doc.size }
}
$results.summary = @{
    totalFiles = $results.documents.Count
    totalLines = $totalLines
    totalSize = $totalSize
    errorCount = $results.errors.Count
}

$results | ConvertTo-Json -Depth 5
