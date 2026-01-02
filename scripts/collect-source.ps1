# Collect actual source code for deep verification
# Fetches key source files to verify code examples in docs

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    
    [string]$Owner = "tenormusica2024",
    [string]$Branch = "main",
    [int]$MaxFiles = 20,
    [int]$MaxFileSize = 50000
)

$results = @{
    source = ""
    type = ""
    sourceFiles = @()
    exports = @()
    routes = @()
    errors = @()
}

# Priority patterns for source files (most important for doc verification)
$priorityPatterns = @(
    # Entry points
    "^(index|main|app|server)\.(js|ts|py|go|rs)$"
    "^src/(index|main|app)\.(js|ts|jsx|tsx)$"
    
    # API routes
    "routes?/"
    "api/"
    "handlers?/"
    "controllers?/"
    
    # Core logic
    "^src/.*\.(js|ts|jsx|tsx)$"
    "^lib/.*\.(js|ts|py)$"
    
    # Config that affects behavior
    "^(vite|webpack|rollup|tsconfig|next)\.config\.(js|ts|mjs)$"
    
    # Scripts mentioned in package.json
    "scripts?/"
)

# Files to skip
$skipPatterns = @(
    "node_modules"
    "\.git/"
    "dist/"
    "build/"
    "\.min\.(js|css)$"
    "\.map$"
    "\.d\.ts$"
    "\.test\.(js|ts)$"
    "\.spec\.(js|ts)$"
    "__tests__"
    "__mocks__"
    "coverage/"
)

function Test-ShouldInclude {
    param([string]$Path)
    
    foreach ($skip in $skipPatterns) {
        if ($Path -match $skip) { return $false }
    }
    
    # Check priority
    foreach ($priority in $priorityPatterns) {
        if ($Path -match $priority) { return $true }
    }
    
    # Include common source extensions
    if ($Path -match "\.(js|ts|jsx|tsx|py|go|rs|java|kt|swift)$") {
        return $true
    }
    
    return $false
}

function Get-PriorityScore {
    param([string]$Path)
    
    $score = 0
    
    # Entry points highest priority
    if ($Path -match "^(index|main|app|server)\.(js|ts|py)$") { $score += 100 }
    if ($Path -match "^src/(index|main|app)") { $score += 90 }
    
    # API/Routes
    if ($Path -match "routes?/|api/|handlers?/") { $score += 80 }
    
    # Core src files
    if ($Path -match "^src/") { $score += 50 }
    if ($Path -match "^lib/") { $score += 40 }
    
    # Scripts
    if ($Path -match "scripts?/") { $score += 60 }
    
    # Config files
    if ($Path -match "\.config\.(js|ts|mjs)$") { $score += 70 }
    
    return $score
}

function Extract-Exports {
    param([string]$Content, [string]$Path)
    
    $exports = @()
    
    # JavaScript/TypeScript exports
    if ($Path -match "\.(js|ts|jsx|tsx)$") {
        # export function name
        $matches = [regex]::Matches($Content, "export\s+(async\s+)?function\s+(\w+)")
        foreach ($m in $matches) {
            $exports += @{ type = "function"; name = $m.Groups[2].Value; file = $Path }
        }
        
        # export const name
        $matches = [regex]::Matches($Content, "export\s+const\s+(\w+)")
        foreach ($m in $matches) {
            $exports += @{ type = "const"; name = $m.Groups[1].Value; file = $Path }
        }
        
        # export class name
        $matches = [regex]::Matches($Content, "export\s+class\s+(\w+)")
        foreach ($m in $matches) {
            $exports += @{ type = "class"; name = $m.Groups[1].Value; file = $Path }
        }
        
        # export default
        $matches = [regex]::Matches($Content, "export\s+default\s+(function\s+)?(\w+)?")
        foreach ($m in $matches) {
            $name = if ($m.Groups[2].Value) { $m.Groups[2].Value } else { "default" }
            $exports += @{ type = "default"; name = $name; file = $Path }
        }
        
        # module.exports
        $matches = [regex]::Matches($Content, "module\.exports\s*=\s*\{([^}]+)\}")
        foreach ($m in $matches) {
            $names = $m.Groups[1].Value -split "," | ForEach-Object { ($_ -split ":")[0].Trim() }
            foreach ($name in $names) {
                if ($name -match "^\w+$") {
                    $exports += @{ type = "commonjs"; name = $name; file = $Path }
                }
            }
        }
    }
    
    # Python exports
    if ($Path -match "\.py$") {
        # def function_name
        $matches = [regex]::Matches($Content, "^def\s+(\w+)\s*\(", [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($m in $matches) {
            $exports += @{ type = "function"; name = $m.Groups[1].Value; file = $Path }
        }
        
        # class ClassName
        $matches = [regex]::Matches($Content, "^class\s+(\w+)", [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($m in $matches) {
            $exports += @{ type = "class"; name = $m.Groups[1].Value; file = $Path }
        }
    }
    
    return $exports
}

function Extract-Routes {
    param([string]$Content, [string]$Path)
    
    $routes = @()
    
    # Express.js routes
    $matches = [regex]::Matches($Content, "(app|router)\.(get|post|put|delete|patch)\s*\(\s*['""]([^'""]+)['""]")
    foreach ($m in $matches) {
        $routes += @{
            method = $m.Groups[2].Value.ToUpper()
            path = $m.Groups[3].Value
            file = $Path
        }
    }
    
    # Next.js API routes (inferred from file path)
    if ($Path -match "pages/api/(.+)\.(js|ts)$") {
        $routePath = "/api/" + ($Matches[1] -replace "\[", ":" -replace "\]", "")
        $routes += @{
            method = "ALL"
            path = $routePath
            file = $Path
            note = "Next.js API route"
        }
    }
    
    # Flask routes
    $matches = [regex]::Matches($Content, "@(app|blueprint)\.route\s*\(\s*['""]([^'""]+)['""]")
    foreach ($m in $matches) {
        $routes += @{
            method = "ALL"
            path = $m.Groups[2].Value
            file = $Path
        }
    }
    
    return $routes
}

# Main execution
$isLocalPath = ($Target -match "[/\\]") -and (Test-Path $Target -ErrorAction SilentlyContinue)

if ($isLocalPath) {
    $results.type = "local"
    $results.source = $Target
    
    $files = Get-ChildItem -Path $Target -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { Test-ShouldInclude $_.FullName.Replace("$Target\", "").Replace("\", "/") } |
        Where-Object { $_.Length -lt $MaxFileSize }
    
    # Sort by priority and take top N
    $sortedFiles = $files | ForEach-Object {
        $relativePath = $_.FullName.Replace("$Target\", "").Replace("\", "/")
        @{
            File = $_
            Path = $relativePath
            Priority = Get-PriorityScore $relativePath
        }
    } | Sort-Object -Property Priority -Descending | Select-Object -First $MaxFiles
    
    foreach ($item in $sortedFiles) {
        $content = Get-Content -Path $item.File.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($content) {
            $results.sourceFiles += @{
                path = $item.Path
                content = $content
                lines = ($content -split "`n").Count
                size = $item.File.Length
                priority = $item.Priority
            }
            
            $results.exports += Extract-Exports -Content $content -Path $item.Path
            $results.routes += Extract-Routes -Content $content -Path $item.Path
        }
    }
}
else {
    $results.type = "github"
    $results.source = "$Owner/$Target"
    
    Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
    
    try {
        $apiPath = "repos/$Owner/$Target/git/trees/${Branch}?recursive=1"
        $treeJson = & 'C:/Program Files/GitHub CLI/gh.exe' api $apiPath 2>$null
        $tree = $treeJson | ConvertFrom-Json
        
        # Filter and prioritize files
        $candidates = $tree.tree | Where-Object {
            $_.type -eq "blob" -and
            (Test-ShouldInclude $_.path) -and
            $_.size -lt $MaxFileSize
        } | ForEach-Object {
            @{
                TreeItem = $_
                Priority = Get-PriorityScore $_.path
            }
        } | Sort-Object -Property Priority -Descending | Select-Object -First $MaxFiles
        
        foreach ($item in $candidates) {
            try {
                $contentJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/contents/$($item.TreeItem.path)?ref=$Branch" 2>$null
                $contentData = $contentJson | ConvertFrom-Json
                
                if ($contentData.encoding -eq "base64") {
                    $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($contentData.content))
                    
                    $results.sourceFiles += @{
                        path = $item.TreeItem.path
                        content = $content
                        lines = ($content -split "`n").Count
                        size = $contentData.size
                        priority = $item.Priority
                    }
                    
                    $results.exports += Extract-Exports -Content $content -Path $item.TreeItem.path
                    $results.routes += Extract-Routes -Content $content -Path $item.TreeItem.path
                }
            }
            catch {
                $results.errors += "Failed to fetch source: $($item.TreeItem.path) - $_"
            }
        }
    }
    catch {
        $results.errors += "Failed to access repository: $_"
    }
}

# Summary
$results.summary = @{
    totalSourceFiles = $results.sourceFiles.Count
    totalExports = $results.exports.Count
    totalRoutes = $results.routes.Count
    totalLines = ($results.sourceFiles | ForEach-Object { $_.lines } | Measure-Object -Sum).Sum
    errorCount = $results.errors.Count
}

$results | ConvertTo-Json -Depth 6
