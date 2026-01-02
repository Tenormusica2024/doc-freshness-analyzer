# Collect code reality from a repository
# Gathers file structure, dependencies, scripts, and key exports

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    
    [string]$Owner = "tenormusica2024",
    [string]$Branch = "main"
)

$results = @{
    source = ""
    type = ""
    fileStructure = @()
    dependencies = @{}
    scripts = @{}
    configFiles = @()
    entryPoints = @()
    errors = @()
}

function Get-LocalReality {
    param([string]$Path)
    
    # File structure (exclude common ignored dirs)
    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "node_modules|\.git|vendor|dist|build|__pycache__|\.pyc|\.venv|venv" } |
        ForEach-Object {
            $_.FullName.Replace("$Path\", "").Replace("\", "/")
        }
    
    $results.fileStructure = $files
    
    # Package.json (Node.js)
    $packageJson = Join-Path $Path "package.json"
    if (Test-Path $packageJson) {
        $pkg = Get-Content $packageJson -Raw | ConvertFrom-Json
        $results.dependencies["npm"] = @{
            dependencies = if ($pkg.dependencies) { $pkg.dependencies.PSObject.Properties.Name } else { @() }
            devDependencies = if ($pkg.devDependencies) { $pkg.devDependencies.PSObject.Properties.Name } else { @() }
            engines = $pkg.engines
        }
        $results.scripts["npm"] = if ($pkg.scripts) { $pkg.scripts.PSObject.Properties | ForEach-Object { @{ $_.Name = $_.Value } } } else { @{} }
        if ($pkg.main) { $results.entryPoints += "main: $($pkg.main)" }
    }
    
    # Check for bun
    if (Test-Path (Join-Path $Path "bun.lockb")) {
        $results.dependencies["runtime"] = "bun"
    }
    elseif (Test-Path (Join-Path $Path "package-lock.json")) {
        $results.dependencies["runtime"] = "npm"
    }
    elseif (Test-Path (Join-Path $Path "yarn.lock")) {
        $results.dependencies["runtime"] = "yarn"
    }
    elseif (Test-Path (Join-Path $Path "pnpm-lock.yaml")) {
        $results.dependencies["runtime"] = "pnpm"
    }
    
    # requirements.txt (Python)
    $requirements = Join-Path $Path "requirements.txt"
    if (Test-Path $requirements) {
        $deps = Get-Content $requirements | Where-Object { $_ -match "^\w" } | ForEach-Object { ($_ -split "[=<>]")[0].Trim() }
        $results.dependencies["pip"] = $deps
    }
    
    # pyproject.toml (Python)
    $pyproject = Join-Path $Path "pyproject.toml"
    if (Test-Path $pyproject) {
        $results.configFiles += "pyproject.toml"
    }
    
    # Cargo.toml (Rust)
    $cargoToml = Join-Path $Path "Cargo.toml"
    if (Test-Path $cargoToml) {
        $results.configFiles += "Cargo.toml"
    }
    
    # go.mod (Go)
    $goMod = Join-Path $Path "go.mod"
    if (Test-Path $goMod) {
        $results.configFiles += "go.mod"
    }
    
    # .env.example
    $envExample = Join-Path $Path ".env.example"
    if (Test-Path $envExample) {
        $envVars = Get-Content $envExample | Where-Object { $_ -match "^[A-Z_]+=" } | ForEach-Object { ($_ -split "=")[0] }
        $results.configFiles += @{
            file = ".env.example"
            variables = $envVars
        }
    }
    
    # Dockerfile
    if (Test-Path (Join-Path $Path "Dockerfile")) {
        $results.configFiles += "Dockerfile"
    }
    
    # GitHub Actions
    $workflows = Join-Path $Path ".github/workflows"
    if (Test-Path $workflows) {
        $workflowFiles = Get-ChildItem $workflows -Filter "*.yml" -ErrorAction SilentlyContinue
        $results.configFiles += $workflowFiles | ForEach-Object { ".github/workflows/$($_.Name)" }
    }
}

function Get-GitHubReality {
    param([string]$Repo, [string]$Owner, [string]$Branch)
    
    Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
    
    # Get file tree
    try {
        $apiPath = "repos/$Owner/$Repo/git/trees/${Branch}?recursive=1"
        $treeJson = & 'C:/Program Files/GitHub CLI/gh.exe' api $apiPath 2>$null
        $tree = $treeJson | ConvertFrom-Json
        
        $results.fileStructure = $tree.tree | 
            Where-Object { $_.type -eq "blob" -and $_.path -notmatch "node_modules|\.git|vendor|dist|build" } |
            ForEach-Object { $_.path }
        
        # Get package.json if exists
        $pkgPath = $tree.tree | Where-Object { $_.path -eq "package.json" }
        if ($pkgPath) {
            $pkgJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Repo/contents/package.json?ref=$Branch" 2>$null
            $pkgData = $pkgJson | ConvertFrom-Json
            if ($pkgData.encoding -eq "base64") {
                $pkgContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pkgData.content))
                $pkg = $pkgContent | ConvertFrom-Json
                
                $results.dependencies["npm"] = @{
                    dependencies = if ($pkg.dependencies) { $pkg.dependencies.PSObject.Properties.Name } else { @() }
                    devDependencies = if ($pkg.devDependencies) { $pkg.devDependencies.PSObject.Properties.Name } else { @() }
                    engines = $pkg.engines
                }
                $results.scripts["npm"] = if ($pkg.scripts) { 
                    $scriptHash = @{}
                    $pkg.scripts.PSObject.Properties | ForEach-Object { $scriptHash[$_.Name] = $_.Value }
                    $scriptHash
                } else { @{} }
            }
        }
        
        # Check for lock files
        $lockFiles = $tree.tree | Where-Object { $_.path -match "^(bun\.lockb|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$" }
        if ($lockFiles) {
            $lockFile = $lockFiles[0].path
            $results.dependencies["runtime"] = switch -Regex ($lockFile) {
                "bun" { "bun" }
                "yarn" { "yarn" }
                "pnpm" { "pnpm" }
                default { "npm" }
            }
        }
        
        # Check for requirements.txt
        $reqPath = $tree.tree | Where-Object { $_.path -eq "requirements.txt" }
        if ($reqPath) {
            $reqJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Repo/contents/requirements.txt?ref=$Branch" 2>$null
            $reqData = $reqJson | ConvertFrom-Json
            if ($reqData.encoding -eq "base64") {
                $reqContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($reqData.content))
                $deps = $reqContent -split "`n" | Where-Object { $_ -match "^\w" } | ForEach-Object { ($_ -split "[=<>]")[0].Trim() }
                $results.dependencies["pip"] = $deps
            }
        }
        
        # Config files detection
        $configPatterns = @("Dockerfile", "\.env\.example", "Cargo\.toml", "go\.mod", "pyproject\.toml")
        $results.configFiles = $tree.tree | 
            Where-Object { $_.type -eq "blob" -and ($configPatterns | Where-Object { $_.path -match $_ }) } |
            ForEach-Object { $_.path }
        
        # GitHub Actions
        $workflows = $tree.tree | Where-Object { $_.path -match "^\.github/workflows/.*\.yml$" }
        $results.configFiles += $workflows | ForEach-Object { $_.path }
    }
    catch {
        $results.errors += "Failed to access repository: $_"
    }
}

# Main execution
# A path must contain \ or / and exist to be considered local
$isLocalPath = ($Target -match "[/\\]") -and (Test-Path $Target -ErrorAction SilentlyContinue)

if ($isLocalPath) {
    $results.type = "local"
    $results.source = $Target
    Get-LocalReality -Path $Target
}
else {
    $results.type = "github"
    $results.source = "$Owner/$Target"
    Get-GitHubReality -Repo $Target -Owner $Owner -Branch $Branch
}

# Summary
$results.summary = @{
    totalFiles = $results.fileStructure.Count
    hasNodeDeps = $null -ne $results.dependencies["npm"]
    hasPythonDeps = $null -ne $results.dependencies["pip"]
    runtime = $results.dependencies["runtime"]
    configFileCount = $results.configFiles.Count
    scriptCount = if ($results.scripts["npm"]) { $results.scripts["npm"].Count } else { 0 }
}

$results | ConvertTo-Json -Depth 5
