# Cache Manager for Incremental Analysis
# Saves/loads analysis results and detects changed files via git diff

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("save", "load", "diff", "invalidate")]
    [string]$Action,
    
    [Parameter(Mandatory=$true)]
    [string]$Target,
    
    [string]$Owner = "tenormusica2024",
    [string]$Branch = "main",
    [string]$CacheDir = "",
    [object]$Data
)

if (-not $CacheDir) {
    $CacheDir = Join-Path $env:USERPROFILE ".doc-freshness-cache"
}

if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

function Get-CacheKey {
    param([string]$Target, [string]$Owner)
    $key = "$Owner-$Target" -replace "[^a-zA-Z0-9\-_]", "_"
    return $key
}

function Get-CachePath {
    param([string]$Target, [string]$Owner)
    $key = Get-CacheKey -Target $Target -Owner $Owner
    return Join-Path $CacheDir "$key.json"
}

function Save-Cache {
    param([string]$Target, [string]$Owner, [string]$Branch, [object]$Data)
    
    $cachePath = Get-CachePath -Target $Target -Owner $Owner
    
    $cacheEntry = @{
        target = $Target
        owner = $Owner
        branch = $Branch
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        commitHash = ""
        data = $Data
    }
    
    $isLocalPath = ($Target -match "[/\\]") -and (Test-Path $Target -ErrorAction SilentlyContinue)
    
    if ($isLocalPath) {
        try {
            $gitHash = git -C $Target rev-parse HEAD 2>$null
            if ($LASTEXITCODE -eq 0) {
                $cacheEntry.commitHash = $gitHash.Trim()
            }
        } catch {}
    } else {
        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        try {
            $refJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/git/ref/heads/$Branch" 2>$null
            $ref = $refJson | ConvertFrom-Json
            $cacheEntry.commitHash = $ref.object.sha
        } catch {}
    }
    
    $cacheEntry | ConvertTo-Json -Depth 10 | Out-File -FilePath $cachePath -Encoding UTF8
    
    return @{
        success = $true
        cachePath = $cachePath
        commitHash = $cacheEntry.commitHash
        timestamp = $cacheEntry.timestamp
    }
}

function Load-Cache {
    param([string]$Target, [string]$Owner)
    
    $cachePath = Get-CachePath -Target $Target -Owner $Owner
    
    if (-not (Test-Path $cachePath)) {
        return @{
            exists = $false
            reason = "No cache file found"
        }
    }
    
    try {
        $cache = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
        return @{
            exists = $true
            cache = $cache
            cachePath = $cachePath
        }
    } catch {
        return @{
            exists = $false
            reason = "Failed to parse cache: $_"
        }
    }
}

function Get-ChangedFiles {
    param([string]$Target, [string]$Owner, [string]$Branch, [string]$FromCommit)
    
    $changedFiles = @()
    $isLocalPath = ($Target -match "[/\\]") -and (Test-Path $Target -ErrorAction SilentlyContinue)
    
    if ($isLocalPath) {
        try {
            $currentHash = git -C $Target rev-parse HEAD 2>$null
            if ($LASTEXITCODE -ne 0) {
                return @{
                    success = $false
                    reason = "Not a git repository"
                    fullRescan = $true
                }
            }
            
            if ($currentHash.Trim() -eq $FromCommit) {
                return @{
                    success = $true
                    changedFiles = @()
                    currentCommit = $currentHash.Trim()
                    noChanges = $true
                }
            }
            
            $diffOutput = git -C $Target diff --name-only $FromCommit HEAD 2>$null
            if ($LASTEXITCODE -eq 0) {
                $changedFiles = $diffOutput -split "`n" | Where-Object { $_ -ne "" }
            }
            
            return @{
                success = $true
                changedFiles = $changedFiles
                currentCommit = $currentHash.Trim()
                previousCommit = $FromCommit
            }
        } catch {
            return @{
                success = $false
                reason = "Git diff failed: $_"
                fullRescan = $true
            }
        }
    } else {
        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        try {
            $refJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/git/ref/heads/$Branch" 2>$null
            $ref = $refJson | ConvertFrom-Json
            $currentHash = $ref.object.sha
            
            if ($currentHash -eq $FromCommit) {
                return @{
                    success = $true
                    changedFiles = @()
                    currentCommit = $currentHash
                    noChanges = $true
                }
            }
            
            $compareJson = & 'C:/Program Files/GitHub CLI/gh.exe' api "repos/$Owner/$Target/compare/${FromCommit}...${currentHash}" 2>$null
            $compare = $compareJson | ConvertFrom-Json
            
            $changedFiles = $compare.files | ForEach-Object { $_.filename }
            
            return @{
                success = $true
                changedFiles = $changedFiles
                currentCommit = $currentHash
                previousCommit = $FromCommit
                totalCommits = $compare.total_commits
            }
        } catch {
            return @{
                success = $false
                reason = "GitHub API failed: $_"
                fullRescan = $true
            }
        }
    }
}

function Invalidate-Cache {
    param([string]$Target, [string]$Owner)
    
    $cachePath = Get-CachePath -Target $Target -Owner $Owner
    
    if (Test-Path $cachePath) {
        Remove-Item -Path $cachePath -Force
        return @{
            success = $true
            message = "Cache invalidated"
        }
    }
    
    return @{
        success = $true
        message = "No cache to invalidate"
    }
}

switch ($Action) {
    "save" {
        if (-not $Data) {
            Write-Error "Data parameter required for save action"
            exit 1
        }
        $result = Save-Cache -Target $Target -Owner $Owner -Branch $Branch -Data $Data
        $result | ConvertTo-Json
    }
    "load" {
        $result = Load-Cache -Target $Target -Owner $Owner
        $result | ConvertTo-Json -Depth 10
    }
    "diff" {
        $cacheResult = Load-Cache -Target $Target -Owner $Owner
        if (-not $cacheResult.exists) {
            @{
                success = $false
                reason = $cacheResult.reason
                fullRescan = $true
            } | ConvertTo-Json
        } else {
            $diffResult = Get-ChangedFiles -Target $Target -Owner $Owner -Branch $Branch -FromCommit $cacheResult.cache.commitHash
            $diffResult | ConvertTo-Json
        }
    }
    "invalidate" {
        $result = Invalidate-Cache -Target $Target -Owner $Owner
        $result | ConvertTo-Json
    }
}
