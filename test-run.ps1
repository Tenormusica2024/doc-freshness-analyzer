Set-Location "C:\Users\Tenormusica\doc-freshness-analyzer-temp\scripts"
Write-Host "=== SmartMode Test ===" -ForegroundColor Cyan
& .\run-analysis.ps1 -Target "ai-trend-daily" -Owner "Tenormusica2024" -Branch "main" 2>&1 | Select-Object -First 50
