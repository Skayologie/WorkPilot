# ==============================================================
#  config.ps1  —  Loads .env and sets process environment vars.
#  Dot-source this at the top of every script:  . "$PSScriptRoot\config.ps1"
# ==============================================================

$_envFile = Join-Path $PSScriptRoot ".env"

if (-not (Test-Path $_envFile)) {
    Write-Host ""
    Write-Host "  ERROR: .env file not found." -ForegroundColor Red
    Write-Host "  Expected: $_envFile" -ForegroundColor DarkGray
    Write-Host "  Copy .env.example to .env and fill in your values." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Get-Content $_envFile | ForEach-Object {
    $line = $_.Trim()
    # skip comments and blank lines
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    if ($line -notmatch '=') { return }
    $key, $val = $line -split '=', 2
    $key = $key.Trim()
    $val = $val.Trim()
    if ($key) {
        [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
    }
}
