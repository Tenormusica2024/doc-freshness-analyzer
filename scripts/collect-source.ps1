# Collect source code with importance scoring
# Fetches ALL source files but only includes content for "active" files
# Active = referenced in package.json scripts, imported, or recently modified

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    
    [string]$Owner = "tenormusica2024",
    [string]$Branch = "main",
    [int]$MaxFileSize = 100000,
    [switch]$SkipContent,
    [switch]$DeepMode,
    [int]$RecentDays = 30,
    [object]$RealityData
)

# Importance score constants (P1: マジックナンバー定数化)
$SCORE_ENTRY_POINT = 50
$SCORE_SCRIPT_REF_FULL = 40
$SCORE_SCRIPT_REF_BASENAME = 30
$SCORE_IMPORT_PER_FILE = 30
$SCORE_IMPORT_MAX = 60
$SCORE_WORKFLOW_REF = 35
$SCORE_RECENT_MODIFIED = 20
$SCORE_CONFIG_FILE = 25
$SCORE_API_ROUTE = 30
$SCORE_ACTIVE_THRESHOLD = 30

# Use ArrayList for better performance (P2: 配列操作効率化)
$results = @{
    source = ""
    type = ""
    sourceFiles = [System.Collections.ArrayList]::new()
    allFiles = [System.Collections.ArrayList]::new()
    exports = [System.Collections.ArrayList]::new()
    routes = [System.Collections.ArrayList]::new()
    imports = [System.Collections.ArrayList]::new()
    externalUrls = [System.Collections.ArrayList]::new()
    potentiallyUnused = [System.Collections.ArrayList]::new()
    legacyFiles = [System.Collections.ArrayList]::new()
    activeFiles = [System.Collections.ArrayList]::new()
    inactiveFiles = [System.Collections.ArrayList]::new()
    errors = [System.Collections.ArrayList]::new()
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

# Entry point patterns (always active)
$entryPointPatterns = @(
    "^index\.(js|ts|jsx|tsx|py|go|rs)$"
    "^main\.(js|ts|jsx|tsx|py|go|rs)$"
    "^app\.(js|ts|jsx|tsx|py)$"
    "^server\.(js|ts|py)$"
    "^src/index\."
    "^src/main\."
    "^src/app\."
    "^pages/_app\."
    "^pages/_document\."
    "^app/layout\."
    "^app/page\."
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

function Test-IsEntryPoint {
    param([string]$Path)
    foreach ($pattern in $entryPointPatterns) {
        if ($Path -match $pattern) { return $true }
    }
    return $false
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

function Get-ImportanceScore {
    param(
        [string]$Path,
        [object]$ScriptRefs,
        [array]$ImportedBy,
        [array]$WorkflowRefs,
        $LastModified,
        [int]$RecentDays
    )
    
    $score = 0
    $reasons = @()
    
    # Entry point check
    if (Test-IsEntryPoint $Path) {
        $score += $SCORE_ENTRY_POINT
        $reasons += "entry-point"
    }
    
    # Referenced in package.json scripts
    $scriptNames = @()
    if ($null -ne $ScriptRefs) {
        if ($ScriptRefs -is [hashtable]) {
            $scriptNames = @($ScriptRefs.Keys)
        } elseif ($ScriptRefs.PSObject -and $ScriptRefs.PSObject.Properties) {
            $scriptNames = @($ScriptRefs.PSObject.Properties.Name)
        }
    }
    # Pre-compute escaped patterns for performance
    $escapedPath = [regex]::Escape($Path)
    $basename = [System.IO.Path]::GetFileName($Path)
    $escapedBasename = [regex]::Escape($basename)
    
    foreach ($scriptName in $scriptNames) {
        $scriptCmd = if ($ScriptRefs -is [hashtable]) { $ScriptRefs[$scriptName] } else { $ScriptRefs.$scriptName }
        if ($scriptCmd -and $scriptCmd -match $escapedPath) {
            $score += $SCORE_SCRIPT_REF_FULL
            $reasons += "script:$scriptName"
            break
        }
        # Also check for file basename
        if ($scriptCmd -and $scriptCmd -match $escapedBasename) {
            $score += $SCORE_SCRIPT_REF_BASENAME
            $reasons += "script-basename:$scriptName"
        }
    }
    
    # Imported by other files (deduplicated count of files that import this one)
    $importCount = 0
    if ($ImportedBy -and $ImportedBy.Count -gt 0) {
        $importCount = @($ImportedBy | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique).Count
    }
    if ($importCount -gt 0) {
        $score += [math]::Min($importCount * $SCORE_IMPORT_PER_FILE, $SCORE_IMPORT_MAX)
        $reasons += "imported:$importCount"
    }
    
    # Referenced in CI/CD workflows (reuse escaped patterns from above)
    if ($WorkflowRefs -and $WorkflowRefs.Count -gt 0) {
        foreach ($wf in $WorkflowRefs) {
            if ($wf -match $escapedPath -or $wf -match $escapedBasename) {
                $score += $SCORE_WORKFLOW_REF
                $reasons += "workflow"
                break
            }
        }
    }
    
    # Recently modified
    if ($LastModified) {
        $daysSinceModified = ((Get-Date) - $LastModified).Days
        if ($daysSinceModified -le $RecentDays) {
            $score += $SCORE_RECENT_MODIFIED
            $reasons += "recent:${daysSinceModified}d"
        }
    }
    
    # Config files are important
    if ($Path -match "\.(json|ya?ml|toml)$" -and $Path -notmatch "package-lock|yarn\.lock") {
        $score += $SCORE_CONFIG_FILE
        $reasons += "config"
    }
    
    # API routes are important
    if ($Path -match "pages/api/|app/.*/route\.|routes/|api/") {
        $score += $SCORE_API_ROUTE
        $reasons += "api-route"
    }
    
    return @{
        score = $score
        reasons = $reasons
        isActive = $score -ge $SCORE_ACTIVE_THRESHOLD
    }
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

function Extract-ExternalUrls {
    param([string]$Content, [string]$Path)
    
    $urls = @()
    
    # Match http/https URLs
    $urlRegex = 'https?://[^\s\)\]\>\"''`]+'
    $matches = [regex]::Matches($Content, $urlRegex)
    
    foreach ($m in $matches) {
        $url = $m.Value -replace '[,;:]+$', ''  # Remove trailing punctuation
        $url = $url -replace '\)$', ''  # Remove trailing parenthesis
        
        # Skip localhost and example domains
        if ($url -match 'localhost|127\.0\.0\.1|example\.com|example\.org|placeholder') { continue }
        
        # Skip common false positives
        if ($url -match '\$\{|\{\{|%s|%d') { continue }  # Template strings
        
        $urls += @{
            url = $url
            file = $Path
            type = if ($url -match "github\.com") { "github" }
                   elseif ($url -match "npmjs\.com|npm\.im") { "npm" }
                   elseif ($url -match "docs\.|documentation") { "docs" }
                   else { "external" }
        }
    }
    
    return $urls
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

function Resolve-ImportToFile {
    param([string]$ImportSource, [string]$ImporterFile, [array]$AllFiles)
    
    if ($ImportSource -notmatch "^\.") { return $null }  # Skip external packages
    
    $importerDir = Split-Path $ImporterFile -Parent
    if ([string]::IsNullOrEmpty($importerDir)) { $importerDir = "." }
    
    $resolved = [System.IO.Path]::Combine($importerDir, $ImportSource)
    $resolved = $resolved -replace "\\", "/" -replace "//+", "/" -replace "/\./", "/" -replace "^\./", ""
    
    $extensions = @("", ".js", ".ts", ".jsx", ".tsx", ".json", "/index.js", "/index.ts", "/index.jsx", "/index.tsx")
    foreach ($ext in $extensions) {
        $candidate = $resolved + $ext
        if ($AllFiles -contains $candidate) {
            return $candidate
        }
    }
    return $null
}

function Find-PotentiallyUnusedFiles {
    param($AllFiles, $Imports, $SourceFiles, $Exports)
    
    $unused = @()
    $importedPaths = @()
    
    foreach ($import in $Imports) {
        $source = $import.source
        if ($source -match "^\.") {
            $importerDir = Split-Path $import.file -Parent
            if ([string]::IsNullOrEmpty($importerDir)) { $importerDir = "." }
            $resolved = [System.IO.Path]::Combine($importerDir, $source)
            $resolved = $resolved -replace "\\", "/" -replace "//+", "/" -replace "/\./", "/" -replace "^\./", ""
            
            $extensions = @("", ".js", ".ts", ".jsx", ".tsx", ".json", "/index.js", "/index.ts")
            foreach ($ext in $extensions) {
                $importedPaths += ($resolved + $ext)
            }
        }
    }
    
    foreach ($file in $SourceFiles) {
        $path = $file.path
        $category = Get-FileCategory $path
        
        if ($category -notin @("javascript", "python", "go", "rust", "jvm", "component")) { continue }
        
        if ($path -match "(index|main|app|server)\.(js|ts|py)$") { continue }
        if ($path -match "\.config\.(js|ts|mjs)$") { continue }
        if ($path -match "^(pages|app)/") { continue }
        
        $isImported = $false
        foreach ($importPath in $importedPaths) {
            if ($path -eq $importPath -or $path -match [regex]::Escape($importPath)) {
                $isImported = $true
                break
            }
        }
        
        if (-not $isImported) {
            $hasExports = ($Exports | Where-Object { $_.file -eq $path }).Count -gt 0
            
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

# Build import dependency map (which files import which)
function Build-ImportMap {
    param([array]$Imports, [array]$AllFilePaths)
    
    $importedBy = @{}
    
    foreach ($import in $Imports) {
        $resolved = Resolve-ImportToFile -ImportSource $import.source -ImporterFile $import.file -AllFiles $AllFilePaths
        if ($resolved) {
            if (-not $importedBy[$resolved]) {
                $importedBy[$resolved] = @()
            }
            $importedBy[$resolved] += $import.file
        }
    }
    
    return $importedBy
}

# Main execution
$isLocalPath = ($Target -match "[/\\]") -and (Test-Path $Target -ErrorAction SilentlyContinue)

# Collect npm scripts and workflow refs from RealityData if provided
$npmScripts = @{}
$workflowContents = @()

if ($RealityData) {
    if ($RealityData.scripts) {
        $scriptsObj = $RealityData.scripts
        if ($scriptsObj.npm) {
            $npmScripts = $scriptsObj.npm
        } elseif ($scriptsObj["npm"]) {
            $npmScripts = $scriptsObj["npm"]
        }
    }
}

# First pass: collect all file paths and basic info
$allFilePaths = @()
$fileInfoMap = @{}

if ($isLocalPath) {
    $results.type = "local"
    $results.source = $Target
    
    $allFilesList = Get-ChildItem -Path $Target -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { 
            $relativePath = $_.FullName.Replace("$Target\", "").Replace("\", "/")
            -not (Test-HardSkip $relativePath)
        }
    
    foreach ($file in $allFilesList) {
        $relativePath = $file.FullName.Replace("$Target\", "").Replace("\", "/")
        $allFilePaths += $relativePath
        $fileInfoMap[$relativePath] = @{
            fullPath = $file.FullName
            size = $file.Length
            lastModified = $file.LastWriteTime
        }
    }
    
    # Get workflow contents for reference checking
    $workflowDir = Join-Path $Target ".github/workflows"
    if (Test-Path $workflowDir) {
        $wfFiles = Get-ChildItem $workflowDir -Filter "*.yml" -ErrorAction SilentlyContinue
        foreach ($wf in $wfFiles) {
            $workflowContents += Get-Content $wf.FullName -Raw -ErrorAction SilentlyContinue
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
        
        $filesToProcess = $tree.tree | Where-Object {
            $_.type -eq "blob" -and -not (Test-HardSkip $_.path)
        }
        
        foreach ($item in $filesToProcess) {
            $allFilePaths += $item.path
            $fileInfoMap[$item.path] = @{
                size = $item.size
                sha = $item.sha
            }
        }
        
        # Get workflow contents
        $wfFiles = $tree.tree | Where-Object { $_.path -match "^\.github/workflows/.*\.yml$" }
        foreach ($wf in $wfFiles) {
            try {
                $wfJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/contents/$($wf.path)?ref=$Branch" 2>$null
                $wfData = $wfJson | ConvertFrom-Json
                if ($wfData.encoding -eq "base64") {
                    $workflowContents += [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($wfData.content))
                }
            } catch {
                [void]$results.errors.Add("[WorkflowFetch] $($wf.path): $($_.Exception.Message)")
            }
        }
    }
    catch {
        [void]$results.errors.Add("[RepoAccess] ${Owner}/${Target}: $($_.Exception.Message)")
    }
}

# Second pass: collect imports first (need this for importance scoring)
$allImports = @()
$tempSourceFiles = @()

foreach ($path in $allFilePaths) {
    if (-not (Test-IsSource $path)) { continue }
    
    $fileInfo = $fileInfoMap[$path]
    if ($fileInfo.size -ge $MaxFileSize) { continue }
    
    $content = $null
    
    if ($isLocalPath) {
        $content = Get-Content -Path $fileInfo.fullPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    else {
        try {
            $contentJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/contents/${path}?ref=$Branch" 2>$null
            $contentData = $contentJson | ConvertFrom-Json
            if ($contentData.encoding -eq "base64") {
                $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($contentData.content))
            }
        } catch {}
    }
    
    if ($content) {
        $imports = Extract-Imports -Content $content -Path $path
        $allImports += $imports
        
        $tempSourceFiles += @{
            path = $path
            content = $content
            size = $fileInfo.size
            lastModified = $fileInfo.lastModified
        }
    }
}

# Build import dependency map
$importedByMap = Build-ImportMap -Imports $allImports -AllFilePaths $allFilePaths

# Third pass: score importance and decide what to include
foreach ($src in $tempSourceFiles) {
    $path = $src.path
    $category = Get-FileCategory $path
    $legacyCheck = Test-IsLegacy $path
    
    # Get files that import this one
    $importedBy = if ($importedByMap[$path]) { $importedByMap[$path] } else { @() }
    
    $importance = Get-ImportanceScore `
        -Path $path `
        -ScriptRefs $npmScripts `
        -ImportedBy $importedBy `
        -WorkflowRefs $workflowContents `
        -LastModified $src.lastModified `
        -RecentDays $RecentDays
    
    $fileInfo = @{
        path = $path
        size = $src.size
        category = $category
        importance = $importance.score
        importanceReasons = $importance.reasons
        isActive = $importance.isActive
    }
    
    if ($src.lastModified) {
        $fileInfo.lastModified = $src.lastModified.ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    [void]$results.allFiles.Add($fileInfo)
    
    if ($legacyCheck.isLegacy) {
        [void]$results.legacyFiles.Add(@{
            path = $path
            reason = $legacyCheck.reason
            size = $src.size
        })
    }
    
    # Include full content for active files or in DeepMode
    if ($importance.isActive -or $DeepMode) {
        [void]$results.sourceFiles.Add(@{
            path = $path
            content = $src.content
            lines = ($src.content -split "`n").Count
            size = $src.size
            category = $category
            importance = $importance.score
            importanceReasons = $importance.reasons
        })
        [void]$results.activeFiles.Add($path)
        
        foreach ($exp in (Extract-Exports -Content $src.content -Path $path)) {
            [void]$results.exports.Add($exp)
        }
        foreach ($route in (Extract-Routes -Content $src.content -Path $path)) {
            [void]$results.routes.Add($route)
        }
        foreach ($url in (Extract-ExternalUrls -Content $src.content -Path $path)) {
            [void]$results.externalUrls.Add($url)
        }
    }
    else {
        # For inactive files, just store metadata
        [void]$results.inactiveFiles.Add(@{
            path = $path
            size = $src.size
            category = $category
            importance = $importance.score
            reason = "Low importance score (below threshold 30)"
        })
    }
}

# Add non-source files to allFiles
foreach ($path in $allFilePaths) {
    if ($results.allFiles | Where-Object { $_.path -eq $path }) { continue }
    
    $fileInfo = $fileInfoMap[$path]
    $category = Get-FileCategory $path
    $legacyCheck = Test-IsLegacy $path
    
    [void]$results.allFiles.Add(@{
        path = $path
        size = $fileInfo.size
        category = $category
        importance = 0
        isActive = $false
    })
    
    if ($legacyCheck.isLegacy) {
        [void]$results.legacyFiles.Add(@{
            path = $path
            reason = $legacyCheck.reason
            size = $fileInfo.size
        })
    }
}

# Store all imports for analysis
$results.imports = $allImports

# Find potentially unused files
$results.potentiallyUnused = Find-PotentiallyUnusedFiles -AllFiles $results.allFiles -Imports $results.imports -SourceFiles $results.sourceFiles -Exports $results.exports

# Summary
$totalLines = 0
foreach ($f in $results.sourceFiles) { if ($f.lines) { $totalLines += $f.lines } }

$results.summary = @{
    totalFilesInRepo = $results.allFiles.Count
    totalSourceFiles = $results.sourceFiles.Count
    activeFileCount = $results.activeFiles.Count
    inactiveFileCount = $results.inactiveFiles.Count
    totalLines = $totalLines
    totalExports = $results.exports.Count
    totalImports = $results.imports.Count
    totalRoutes = $results.routes.Count
    totalExternalUrls = $results.externalUrls.Count
    legacyFileCount = $results.legacyFiles.Count
    potentiallyUnusedCount = $results.potentiallyUnused.Count
    errorCount = $results.errors.Count
    mode = if ($DeepMode) { "deep" } else { "smart" }
    categorySummary = $results.allFiles | Group-Object -Property category | ForEach-Object {
        @{ category = $_.Name; count = $_.Count }
    }
}

$results | ConvertTo-Json -Depth 6
