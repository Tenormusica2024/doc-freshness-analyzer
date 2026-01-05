# HTTP HEAD URL Verification Script
# Checks external URLs for dead links with rate limiting

param(
    [Parameter(ValueFromPipeline=$true)]
    [object]$UrlData,
    
    [int]$TimeoutSeconds = 10,
    [int]$DelayMs = 500,
    [switch]$JsonInput,
    [string]$InputFile
)

$results = @{
    verified = @()
    deadLinks = @()
    redirects = @()
    errors = @()
    summary = @{
        total = 0
        alive = 0
        dead = 0
        redirected = 0
        errored = 0
        skipped = 0
    }
}

$skipDomains = @(
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "example.com",
    "example.org",
    "placeholder.com"
)

$rateLimitTracker = @{}

function Test-UrlAlive {
    param(
        [string]$Url,
        [int]$Timeout
    )
    
    try {
        $uri = [System.Uri]::new($Url)
        $domain = $uri.Host
        
        foreach ($skip in $skipDomains) {
            if ($domain -match $skip) {
                return @{
                    status = "skipped"
                    reason = "Skipped domain: $skip"
                }
            }
        }
        
        if ($rateLimitTracker[$domain]) {
            $lastRequest = $rateLimitTracker[$domain]
            $elapsed = (Get-Date) - $lastRequest
            if ($elapsed.TotalMilliseconds -lt $DelayMs) {
                Start-Sleep -Milliseconds ($DelayMs - $elapsed.TotalMilliseconds)
            }
        }
        $rateLimitTracker[$domain] = Get-Date
        
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "HEAD"
        $request.Timeout = $Timeout * 1000
        $request.AllowAutoRedirect = $false
        $request.UserAgent = "doc-freshness-analyzer/1.0 (URL verification bot)"
        
        try {
            $response = $request.GetResponse()
            $statusCode = [int]$response.StatusCode
            $response.Close()
            
            if ($statusCode -ge 200 -and $statusCode -lt 300) {
                return @{
                    status = "alive"
                    statusCode = $statusCode
                }
            } elseif ($statusCode -ge 300 -and $statusCode -lt 400) {
                $location = $response.Headers["Location"]
                return @{
                    status = "redirect"
                    statusCode = $statusCode
                    redirectTo = $location
                }
            } else {
                return @{
                    status = "dead"
                    statusCode = $statusCode
                    reason = "HTTP $statusCode"
                }
            }
        } catch [System.Net.WebException] {
            $webEx = $_.Exception
            if ($webEx.Response) {
                $statusCode = [int]$webEx.Response.StatusCode
                
                if ($statusCode -ge 300 -and $statusCode -lt 400) {
                    $location = $webEx.Response.Headers["Location"]
                    return @{
                        status = "redirect"
                        statusCode = $statusCode
                        redirectTo = $location
                    }
                }
                
                return @{
                    status = "dead"
                    statusCode = $statusCode
                    reason = "HTTP $statusCode"
                }
            }
            
            if ($webEx.Status -eq [System.Net.WebExceptionStatus]::Timeout) {
                return @{
                    status = "error"
                    reason = "Request timeout ($Timeout seconds)"
                }
            }
            
            return @{
                status = "error"
                reason = $webEx.Message
            }
        }
    } catch {
        return @{
            status = "error"
            reason = $_.Exception.Message
        }
    }
}

$urls = @()

if ($InputFile -and (Test-Path $InputFile)) {
    $inputData = Get-Content -Path $InputFile -Raw | ConvertFrom-Json
    if ($inputData.externalUrls) {
        $urls = $inputData.externalUrls
    } elseif ($inputData -is [array]) {
        $urls = $inputData
    }
} elseif ($JsonInput) {
    $inputJson = $input | Out-String
    $inputData = $inputJson | ConvertFrom-Json
    if ($inputData.externalUrls) {
        $urls = $inputData.externalUrls
    } elseif ($inputData -is [array]) {
        $urls = $inputData
    }
} elseif ($UrlData) {
    if ($UrlData -is [array]) {
        $urls = $UrlData
    } else {
        $urls = @($UrlData)
    }
}

$uniqueUrls = @{}
foreach ($urlItem in $urls) {
    $url = if ($urlItem.url) { $urlItem.url } else { $urlItem.ToString() }
    if (-not $uniqueUrls[$url]) {
        $uniqueUrls[$url] = @{
            url = $url
            sources = @()
        }
    }
    if ($urlItem.file) {
        $uniqueUrls[$url].sources += $urlItem.file
    }
}

$results.summary.total = $uniqueUrls.Count

Write-Host "Verifying $($uniqueUrls.Count) unique URLs..." -ForegroundColor Cyan

$counter = 0
foreach ($entry in $uniqueUrls.Values) {
    $counter++
    $url = $entry.url
    
    $percentComplete = if ($uniqueUrls.Count -gt 0) { ($counter / $uniqueUrls.Count) * 100 } else { 100 }
    Write-Progress -Activity "Verifying URLs" -Status "$counter / $($uniqueUrls.Count): $url" -PercentComplete $percentComplete
    
    $checkResult = Test-UrlAlive -Url $url -Timeout $TimeoutSeconds
    
    $resultEntry = @{
        url = $url
        sources = $entry.sources
        checkedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    switch ($checkResult.status) {
        "alive" {
            $resultEntry.status = "alive"
            $resultEntry.statusCode = $checkResult.statusCode
            $results.verified += $resultEntry
            $results.summary.alive++
            Write-Host "  [OK] $url" -ForegroundColor Green
        }
        "dead" {
            $resultEntry.status = "dead"
            $resultEntry.statusCode = $checkResult.statusCode
            $resultEntry.reason = $checkResult.reason
            $resultEntry.suggestedFix = "Remove or update URL: $url"
            $results.deadLinks += $resultEntry
            $results.summary.dead++
            Write-Host "  [DEAD] $url - $($checkResult.reason)" -ForegroundColor Red
        }
        "redirect" {
            $resultEntry.status = "redirect"
            $resultEntry.statusCode = $checkResult.statusCode
            $resultEntry.redirectTo = $checkResult.redirectTo
            $resultEntry.suggestedFix = "Update URL from '$url' to '$($checkResult.redirectTo)'"
            $results.redirects += $resultEntry
            $results.summary.redirected++
            Write-Host "  [REDIRECT] $url -> $($checkResult.redirectTo)" -ForegroundColor Yellow
        }
        "error" {
            $resultEntry.status = "error"
            $resultEntry.reason = $checkResult.reason
            $results.errors += $resultEntry
            $results.summary.errored++
            Write-Host "  [ERROR] $url - $($checkResult.reason)" -ForegroundColor Magenta
        }
        "skipped" {
            $results.summary.skipped++
            Write-Host "  [SKIP] $url - $($checkResult.reason)" -ForegroundColor Gray
        }
    }
}

Write-Progress -Activity "Verifying URLs" -Completed

Write-Host ""
Write-Host "=== URL Verification Summary ===" -ForegroundColor Cyan
Write-Host "Total: $($results.summary.total)" -ForegroundColor White
Write-Host "Alive: $($results.summary.alive)" -ForegroundColor Green
Write-Host "Dead: $($results.summary.dead)" -ForegroundColor Red
Write-Host "Redirected: $($results.summary.redirected)" -ForegroundColor Yellow
Write-Host "Errors: $($results.summary.errored)" -ForegroundColor Magenta
Write-Host "Skipped: $($results.summary.skipped)" -ForegroundColor Gray

$results | ConvertTo-Json -Depth 5
