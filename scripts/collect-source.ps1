# Collect ALL source code for comprehensive verification
# Fetches all source files + detects potentially unused/orphan files

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    
    [string]$Owner = "tenormusica2024",
    [string]$Branch = "main",
    [int]$MaxFileSize = 100000,
    [switch]$SkipContent
)

$results = @{
    source = ""
    type = ""
    sourceFiles = @()
    allFiles = @()
    exports = @()
    routes = @()
    imports = @()
    potentiallyUnused = @()
    legacyFiles = @()
    errors = @()
}

# Files to completely skip (not even list)
$hardSkipPatterns = @(
    "^node_modules/"
    "^\.git/"
    "^dist/"
    "^build/"
    "^\.next/"
    "^__pycache__/"
    "^\.pytest_cache/"
    "^coverage/"
    "^\.nyc_output/"
    "^vendor/"
    "\.min\.(js|css)$"
    "\.map$"
    "\.lock$"
    "package-lock\.json$"
    "yarn\.lock$"
    "pnpm-lock\.yaml$"
    "bun\.lockb$"
)

# Patterns that suggest legacy/unused files
$legacyPatterns = @(
    @{ pattern = "\.bak$"; reason = "Backup file" }
    @{ pattern = "\.old$"; reason = "Old version file" }
    @{ pattern = "\.orig$"; reason = "Original backup file" }
    @{ pattern = "\.backup$"; reason = "Backup file" }
    @{ pattern = "\.deprecated"; reason = "Deprecated file" }
    @{ pattern = "legacy"; reason = "Legacy in filename" }
    @{ pattern = "unused"; reason = "Unused in filename" }
    @{ pattern = "\.tmp$"; reason = "Temporary file" }
    @{ pattern = "\.temp$"; reason = "Temporary file" }
    @{ pattern = "\.swp$"; reason = "Vim swap file" }
    @{ pattern = "~$"; reason = "Editor backup file" }
    @{ pattern = "\.DS_Store$"; reason = "macOS metadata" }
    @{ pattern = "Thumbs\.db$"; reason = "Windows metadata" }
)

# Source file extensions (fetch content for these)
$sourceExtensions = @(
    "\.js$", "\.jsx$", "\.ts$", "\.tsx$", "\.mjs$", "\.cjs$"
    "\.py$", "\.pyw$"
    "\.go$"
    "\.rs$"
    "\.java$", "\.kt$", "\.scala$"
    "\.swift$"
    "\.rb$"
    "\.php$"
    "\.c$", "\.cpp$", "\.h$", "\.hpp$"
    "\.cs$"
    "\.vue$", "\.svelte$"
)

# Config/important files (also fetch content)
$configPatterns = @(
    "\.json$"
    "\.ya?ml$"
    "\.toml$"
    "\.ini$"
    "\.env"
    "\.config\."
    "Dockerfile"
    "docker-compose"
    "Makefile$"
    "\.sh$"
    "\.ps1$"
    "\.bat$"
    "\.cmd$"
)

function Test-HardSkip {
    param([string]$Path)
    foreach ($skip in $hardSkipPatterns) {
        if ($Path -match $skip) { return $true }
    }
    return $false
}

function Test-IsSource {
    param([string]$Path)
    foreach ($ext in $sourceExtensions) {
        if ($Path -match $ext) { return $true }
    }
    foreach ($cfg in $configPatterns) {
        if ($Path -match $cfg) { return $true }
    }
    return $false
}

function Test-IsLegacy {
    param([string]$Path)
    foreach ($legacy in $legacyPatterns) {
        if ($Path -match $legacy.pattern) {
            return @{ isLegacy = $true; reason = $legacy.reason }
        }
    }
    return @{ isLegacy = $false; reason = "" }
}

function Get-FileCategory {
    param([string]$Path)
    
    if ($Path -match "\.(js|jsx|ts|tsx|mjs|cjs)$") { return "javascript" }
    if ($Path -match "\.py$") { return "python" }
    if ($Path -match "\.go$") { return "go" }
    if ($Path -match "\.rs$") { return "rust" }
    if ($Path -match "\.(java|kt|scala)$") { return "jvm" }
    if ($Path -match "\.swift$") { return "swift" }
    if ($Path -match "\.rb$") { return "ruby" }
    if ($Path -match "\.php$") { return "php" }
    if ($Path -match "\.(c|cpp|h|hpp)$") { return "cpp" }
    if ($Path -match "\.cs$") { return "csharp" }
    if ($Path -match "\.(vue|svelte)$") { return "component" }
    if ($Path -match "\.json$") { return "config-json" }
    if ($Path -match "\.ya?ml$") { return "config-yaml" }
    if ($Path -match "\.(md|txt|rst)$") { return "documentation" }
    if ($Path -match "\.(css|scss|sass|less)$") { return "style" }
    if ($Path -match "\.(html|htm)$") { return "html" }
    if ($Path -match "\.(png|jpg|jpeg|gif|svg|ico|webp)$") { return "image" }
    if ($Path -match "\.(woff|woff2|ttf|eot|otf)$") { return "font" }
    return "other"
}

function Extract-Exports {
    param([string]$Content, [string]$Path)
    
    $exports = @()
    
    if ($Path -match "\.(js|ts|jsx|tsx|mjs|cjs)$") {
        # export function/const/class
        $regexes = @(
            @{ regex = "export\s+(async\s+)?function\s+(\w+)"; group = 2; type = "function" }
            @{ regex = "export\s+const\s+(\w+)"; group = 1; type = "const" }
            @{ regex = "export\s+let\s+(\w+)"; group = 1; type = "let" }
            @{ regex = "export\s+class\s+(\w+)"; group = 1; type = "class" }
            @{ regex = "export\s+interface\s+(\w+)"; group = 1; type = "interface" }
            @{ regex = "export\s+type\s+(\w+)"; group = 1; type = "type" }
            @{ regex = "export\s+enum\s+(\w+)"; group = 1; type = "enum" }
        )
        
        foreach ($r in $regexes) {
            $matches = [regex]::Matches($Content, $r.regex)
            foreach ($m in $matches) {
                $exports += @{ type = $r.type; name = $m.Groups[$r.group].Value; file = $Path }
            }
        }
        
        # export default
        $defaultMatches = [regex]::Matches($Content, "export\s+default\s+(?:function\s+|class\s+)?(\w+)?")
        foreach ($m in $defaultMatches) {
            $name = if ($m.Groups[1].Value) { $m.Groups[1].Value } else { "default" }
            $exports += @{ type = "default"; name = $name; file = $Path }
        }
        
        # module.exports
        $cjsMatches = [regex]::Matches($Content, "module\.exports\s*=\s*\{([^}]+)\}")
        foreach ($m in $cjsMatches) {
            $names = $m.Groups[1].Value -split "," | ForEach-Object { ($_ -split ":")[0].Trim() }
            foreach ($name in $names) {
                if ($name -match "^\w+$") {
                    $exports += @{ type = "commonjs"; name = $name; file = $Path }
                }
            }
        }
    }
    
    if ($Path -match "\.py$") {
        $defMatches = [regex]::Matches($Content, "^def\s+(\w+)\s*\(", [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($m in $defMatches) {
            $exports += @{ type = "function"; name = $m.Groups[1].Value; file = $Path }
        }
        
        $classMatches = [regex]::Matches($Content, "^class\s+(\w+)", [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($m in $classMatches) {
            $exports += @{ type = "class"; name = $m.Groups[1].Value; file = $Path }
        }
    }
    
    return $exports
}

function Extract-Imports {
    param([string]$Content, [string]$Path)
    
    $imports = @()
    
    if ($Path -match "\.(js|ts|jsx|tsx|mjs|cjs)$") {
        # ES6 imports
        $esImports = [regex]::Matches($Content, "import\s+.*?\s+from\s+['""]([^'""]+)['""]")
        foreach ($m in $esImports) {
            $imports += @{ source = $m.Groups[1].Value; file = $Path; type = "es6" }
        }
        
        # require
        $requireImports = [regex]::Matches($Content, "require\s*\(\s*['""]([^'""]+)['""]\s*\)")
        foreach ($m in $requireImports) {
            $imports += @{ source = $m.Groups[1].Value; file = $Path; type = "commonjs" }
        }
        
        # dynamic import
        $dynamicImports = [regex]::Matches($Content, "import\s*\(\s*['""]([^'""]+)['""]\s*\)")
        foreach ($m in $dynamicImports) {
            $imports += @{ source = $m.Groups[1].Value; file = $Path; type = "dynamic" }
        }
    }
    
    if ($Path -match "\.py$") {
        $pyImports = [regex]::Matches($Content, "^(?:from\s+(\S+)\s+)?import\s+(.+)$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($m in $pyImports) {
            $module = if ($m.Groups[1].Value) { $m.Groups[1].Value } else { $m.Groups[2].Value.Split(",")[0].Trim() }
            $imports += @{ source = $module; file = $Path; type = "python" }
        }
    }
    
    return $imports
}

function Extract-Routes {
    param([string]$Content, [string]$Path)
    
    $routes = @()
    
    # Express.js
    $expressRoutes = [regex]::Matches($Content, "(app|router)\.(get|post|put|delete|patch|all|use)\s*\(\s*['""]([^'""]+)['""]")
    foreach ($m in $expressRoutes) {
        $routes += @{ method = $m.Groups[2].Value.ToUpper(); path = $m.Groups[3].Value; file = $Path; framework = "express" }
    }
    
    # Next.js API routes
    if ($Path -match "pages/api/(.+)\.(js|ts)$") {
        $routePath = "/api/" + ($Matches[1] -replace "\[", ":" -replace "\]", "")
        $routes += @{ method = "ALL"; path = $routePath; file = $Path; framework = "nextjs" }
    }
    
    # Next.js App Router
    if ($Path -match "app/(.+)/route\.(js|ts)$") {
        $routePath = "/" + $Matches[1] -replace "\[", ":" -replace "\]", ""
        $routes += @{ method = "ALL"; path = $routePath; file = $Path; framework = "nextjs-app" }
    }
    
    # Flask
    $flaskRoutes = [regex]::Matches($Content, "@(?:app|blueprint|bp)\.route\s*\(\s*['""]([^'""]+)['""]")
    foreach ($m in $flaskRoutes) {
        $routes += @{ method = "ALL"; path = $m.Groups[1].Value; file = $Path; framework = "flask" }
    }
    
    # FastAPI
    $fastapiRoutes = [regex]::Matches($Content, "@(?:app|router)\.(get|post|put|delete|patch)\s*\(\s*['""]([^'""]+)['""]")
    foreach ($m in $fastapiRoutes) {
        $routes += @{ method = $m.Groups[1].Value.ToUpper(); path = $m.Groups[2].Value; file = $Path; framework = "fastapi" }
    }
    
    return $routes
}

function Find-PotentiallyUnusedFiles {
    param($AllFiles, $Imports, $SourceFiles)
    
    $unused = @()
    $importedPaths = @()
    
    # Normalize import paths to file paths
    foreach ($import in $Imports) {
        $source = $import.source
        if ($source -match "^\.") {
            # Relative import - resolve from importing file's directory
            $importerDir = Split-Path $import.file -Parent
            $resolved = Join-Path $importerDir $source
            $resolved = $resolved -replace "\\", "/" -replace "/\./", "/" -replace "^./", ""
            
            # Try with extensions
            $extensions = @("", ".js", ".ts", ".jsx", ".tsx", ".json", "/index.js", "/index.ts")
            foreach ($ext in $extensions) {
                $importedPaths += ($resolved + $ext)
            }
        }
    }
    
    # Find source files that are never imported
    foreach ($file in $SourceFiles) {
        $path = $file.path
        $category = Get-FileCategory $path
        
        # Skip non-importable files
        if ($category -notin @("javascript", "python", "go", "rust", "jvm", "component")) { continue }
        
        # Skip entry points and config
        if ($path -match "(index|main|app|server)\.(js|ts|py)$") { continue }
        if ($path -match "\.config\.(js|ts|mjs)$") { continue }
        if ($path -match "^(pages|app)/") { continue }  # Next.js routes
        
        # Check if imported
        $isImported = $false
        foreach ($importPath in $importedPaths) {
            if ($path -eq $importPath -or $path -match [regex]::Escape($importPath)) {
                $isImported = $true
                break
            }
        }
        
        if (-not $isImported) {
            # Check if it exports anything (if no exports, might be unused)
            $hasExports = ($results.exports | Where-Object { $_.file -eq $path }).Count -gt 0
            
            $unused += @{
                path = $path
                category = $category
                hasExports = $hasExports
                size = $file.size
                reason = if ($hasExports) { "Has exports but not imported anywhere" } else { "No exports and not imported" }
            }
        }
    }
    
    return $unused
}

# Main execution
$isLocalPath = ($Target -match "[/\\]") -and (Test-Path $Target -ErrorAction SilentlyContinue)

if ($isLocalPath) {
    $results.type = "local"
    $results.source = $Target
    
    # Get ALL files first
    $allFilesList = Get-ChildItem -Path $Target -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { 
            $relativePath = $_.FullName.Replace("$Target\", "").Replace("\", "/")
            -not (Test-HardSkip $relativePath)
        }
    
    foreach ($file in $allFilesList) {
        $relativePath = $file.FullName.Replace("$Target\", "").Replace("\", "/")
        $category = Get-FileCategory $relativePath
        $legacyCheck = Test-IsLegacy $relativePath
        
        $fileInfo = @{
            path = $relativePath
            size = $file.Length
            category = $category
            lastModified = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        $results.allFiles += $fileInfo
        
        if ($legacyCheck.isLegacy) {
            $results.legacyFiles += @{
                path = $relativePath
                reason = $legacyCheck.reason
                size = $file.Length
            }
        }
        
        # Fetch content for source files
        if ((Test-IsSource $relativePath) -and $file.Length -lt $MaxFileSize -and -not $SkipContent) {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($content) {
                $results.sourceFiles += @{
                    path = $relativePath
                    content = $content
                    lines = ($content -split "`n").Count
                    size = $file.Length
                    category = $category
                }
                
                $results.exports += Extract-Exports -Content $content -Path $relativePath
                $results.imports += Extract-Imports -Content $content -Path $relativePath
                $results.routes += Extract-Routes -Content $content -Path $relativePath
            }
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
        
        # Process ALL files
        $filesToProcess = $tree.tree | Where-Object {
            $_.type -eq "blob" -and -not (Test-HardSkip $_.path)
        }
        
        foreach ($item in $filesToProcess) {
            $category = Get-FileCategory $item.path
            $legacyCheck = Test-IsLegacy $item.path
            
            $fileInfo = @{
                path = $item.path
                size = $item.size
                category = $category
            }
            
            $results.allFiles += $fileInfo
            
            if ($legacyCheck.isLegacy) {
                $results.legacyFiles += @{
                    path = $item.path
                    reason = $legacyCheck.reason
                    size = $item.size
                }
            }
            
            # Fetch content for source files
            if ((Test-IsSource $item.path) -and $item.size -lt $MaxFileSize -and -not $SkipContent) {
                try {
                    $contentJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/contents/$($item.path)?ref=$Branch" 2>$null
                    $contentData = $contentJson | ConvertFrom-Json
                    
                    if ($contentData.encoding -eq "base64") {
                        $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($contentData.content))
                        
                        $results.sourceFiles += @{
                            path = $item.path
                            content = $content
                            lines = ($content -split "`n").Count
                            size = $contentData.size
                            category = $category
                        }
                        
                        $results.exports += Extract-Exports -Content $content -Path $item.path
                        $results.imports += Extract-Imports -Content $content -Path $item.path
                        $results.routes += Extract-Routes -Content $content -Path $item.path
                    }
                }
                catch {
                    $results.errors += "Failed to fetch: $($item.path) - $_"
                }
            }
        }
    }
    catch {
        $results.errors += "Failed to access repository: $_"
    }
}

# Find potentially unused files
$results.potentiallyUnused = Find-PotentiallyUnusedFiles -AllFiles $results.allFiles -Imports $results.imports -SourceFiles $results.sourceFiles

# Summary
$totalLines = 0
foreach ($f in $results.sourceFiles) { if ($f.lines) { $totalLines += $f.lines } }

$results.summary = @{
    totalFilesInRepo = $results.allFiles.Count
    totalSourceFiles = $results.sourceFiles.Count
    totalLines = $totalLines
    totalExports = $results.exports.Count
    totalImports = $results.imports.Count
    totalRoutes = $results.routes.Count
    legacyFileCount = $results.legacyFiles.Count
    potentiallyUnusedCount = $results.potentiallyUnused.Count
    errorCount = $results.errors.Count
    categorySummary = $results.allFiles | Group-Object -Property category | ForEach-Object {
        @{ category = $_.Name; count = $_.Count }
    }
}

$results | ConvertTo-Json -Depth 6
