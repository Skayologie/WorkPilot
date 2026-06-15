# ==============================================================
#  WorkPilot - work.ps1
#  Author  : Jawad Boulmal
#  GitHub  : https://github.com/Skayologie
#  Project : https://github.com/Skayologie/WorkPilot
# ==============================================================

param(
    [Parameter(Position=0)] [string]$Cmd = "help",
    [Parameter(Position=1)] [string]$Arg = ""
)

. "$PSScriptRoot\config.ps1"

$PROJECT_RUN       = $env:PROJECT_RUN
$PROJECT_WORKSPACE = $env:PROJECT_WORKSPACE
$WSL_DISTRO        = if ($env:WSL_DISTRO) { $env:WSL_DISTRO } else { "Ubuntu" }
$TASK_PREFIX       = if ($env:TASK_PREFIX) { $env:TASK_PREFIX } else { "MyWorkBot" }
$CLAUDE            = $env:CLAUDE_EXE
$CHROME_TABS       = if ($env:CHROME_TABS) { $env:CHROME_TABS -split '\|' } else { @() }

function Log([string]$label, [string]$msg, [string]$color = "White") {
    Write-Host ("  [{0,-20}] {1}" -f $label, $msg) -ForegroundColor $color
}

function Send-Telegram([string]$text) {
    $token  = $env:TELEGRAM_TOKEN
    $chatId = $env:TELEGRAM_CHAT_ID
    if (-not $token -or -not $chatId) { return }
    $clean = ($text -replace '\x1b\[[0-9;]*[mK]', '').Trim()
    if ($clean.Length -gt 4000) { $clean = $clean.Substring(0, 4000) + "`n..." }
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" `
            -Method Post -Body @{ chat_id = $chatId; text = $clean } | Out-Null
    } catch {}
}

function Banner([string]$title) {
    Write-Host ""
    Write-Host "  WorkPilot  |  $title" -ForegroundColor Cyan
    Write-Host "  =============================" -ForegroundColor DarkGray
    Write-Host ""
}

function Wait-DockerReady {
    $running = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if ($running) { Log "Docker Desktop" "already running" "Yellow"; return }

    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    Log "Docker Desktop" "launched, waiting for engine..." "Green"

    $ready = $false; $attempts = 0
    while (-not $ready -and $attempts -lt 30) {
        $r = wsl -d $WSL_DISTRO -e bash -c "docker info > /dev/null 2>&1 && echo ok" 2>$null
        if ($r -eq "ok") { $ready = $true } else { Start-Sleep -Seconds 3; $attempts++ }
    }
    if ($ready)  { Log "Docker Desktop" "engine ready" "Green" }
    else         { Log "Docker Desktop" "engine not ready after 90s, continuing anyway" "Red" }
}

function Invoke-Begin {
    Banner "Starting work environment..."

    if ($CHROME_TABS.Count -gt 0) {
        Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" -ArgumentList $CHROME_TABS
        Log "Chrome" "launched ($($CHROME_TABS.Count) tabs)" "Green"
    }

    Start-Process powershell -WindowStyle Hidden `
        -ArgumentList "-NoProfile", "-Command", "Start-Process '$env:LOCALAPPDATA\Microsoft\WindowsApps\Slack.exe'"
    Log "Slack" "launched" "Green"

    Wait-DockerReady

    if ($PROJECT_WORKSPACE -and (Test-Path $PROJECT_WORKSPACE)) {
        Start-Process "code" -ArgumentList $PROJECT_WORKSPACE
        Log "VS Code" "launched ($PROJECT_WORKSPACE)" "Green"
    }

    if ($PROJECT_RUN -and (Test-Path $PROJECT_RUN)) {
        Banner "Starting project services..."
        & $PROJECT_RUN up
        Write-Host ""
        & $PROJECT_RUN status
    }

    Write-Host "  =============================" -ForegroundColor DarkGray
    Write-Host "  Work environment is ready!" -ForegroundColor Green
    Write-Host ""
}

function Kill-App([string]$label, [string[]]$exeNames) {
    $found = $false
    foreach ($exe in $exeNames) {
        taskkill /F /IM "$exe.exe" /T 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $found = $true }
    }
    if ($found) { Log $label "closed" "Red" }
    else        { Log $label "not running" "DarkGray" }
}

function Invoke-Done {
    Banner "Stopping work environment..."

    if ($PROJECT_RUN -and (Test-Path $PROJECT_RUN)) {
        Log "project" "stopping all services..." "Yellow"
        & $PROJECT_RUN down
        Write-Host ""
    }

    Banner "Closing apps..."

    Kill-App "Chrome"         @("chrome")
    Kill-App "Slack"          @("slack")
    Kill-App "VS Code"        @("Code")
    Kill-App "Docker Desktop" @("Docker Desktop", "com.docker.backend", "com.docker.build", "com.docker.proxy", "docker-sandbox", "dockerd")

    $shell = New-Object -ComObject Shell.Application
    $explorerWindows = @($shell.Windows() | Where-Object { $_.Name -eq "File Explorer" })
    if ($explorerWindows.Count -gt 0) {
        $explorerWindows | ForEach-Object { $_.Quit() }
        Log "File Explorer" "closed ($($explorerWindows.Count) window(s))" "Red"
    } else {
        Log "File Explorer" "not running" "DarkGray"
    }

    $currentPid = $PID
    Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne $currentPid } |
        ForEach-Object { taskkill /F /PID $_.Id /T 2>$null | Out-Null }
    Get-Process -Name "cmd" -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne $currentPid } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Log "Terminal windows" "closed" "Red"

    Write-Host "  =============================" -ForegroundColor DarkGray
    Write-Host "  Work environment stopped. See you!" -ForegroundColor Red
    Write-Host ""
    Start-Sleep -Seconds 2
    [System.Environment]::Exit(0)
}

function Invoke-Status {
    Banner "Work environment status"

    foreach ($name in @("chrome", "slack", "Code", "Docker Desktop")) {
        $p = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($p) { Log $name "running" "Green" }
        else    { Log $name "not running" "DarkGray" }
    }

    if ($PROJECT_RUN -and (Test-Path $PROJECT_RUN)) {
        Write-Host ""
        & $PROJECT_RUN status
    }
}

function Invoke-Restart {
    if (-not ($PROJECT_RUN -and (Test-Path $PROJECT_RUN))) {
        Write-Host "  PROJECT_RUN not configured in .env" -ForegroundColor Yellow; return
    }
    if ($Arg -eq "") {
        Banner "Restarting all services..."
        & $PROJECT_RUN restart
    } else {
        Banner "Restarting $Arg..."
        & $PROJECT_RUN $Arg restart
    }
}

function Invoke-Logs {
    if (-not ($PROJECT_RUN -and (Test-Path $PROJECT_RUN))) {
        Write-Host "  PROJECT_RUN not configured in .env" -ForegroundColor Yellow; return
    }
    if ($Arg -eq "") { Write-Host "  Usage: work logs <service>" -ForegroundColor Yellow; return }
    & $PROJECT_RUN logs $Arg
}

function Invoke-Doctor {
    Banner "Health check..."

    foreach ($name in @("chrome", "slack", "Code", "Docker Desktop")) {
        $p = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($p) { Log $name "running" "Green" } else { Log $name "not running" "DarkGray" }
    }
    Write-Host ""

    $wsl = wsl -d $WSL_DISTRO -e bash -c "echo ok" 2>$null
    if ($wsl -eq "ok") { Log "WSL ($WSL_DISTRO)" "accessible" "Green" }
    else               { Log "WSL ($WSL_DISTRO)" "not accessible" "Red" }

    $engine = wsl -d $WSL_DISTRO -e bash -c "docker info > /dev/null 2>&1 && echo ok" 2>$null
    if ($engine -eq "ok") { Log "Docker Engine" "running" "Green" }
    else                  { Log "Docker Engine" "not running" "Red" }

    if ($PROJECT_RUN -and (Test-Path $PROJECT_RUN)) {
        Write-Host ""
        & $PROJECT_RUN status
        Write-Host ""
    }

    foreach ($portVar in @("API_PORT","FRONTEND_PORT","FRONTEND2_PORT")) {
        $port = [System.Environment]::GetEnvironmentVariable($portVar, 'Process')
        if (-not $port) { continue }
        try {
            $res = Invoke-WebRequest -Uri "http://localhost:$port" -TimeoutSec 3 -ErrorAction Stop
            Log "localhost:$port" "responding (HTTP $($res.StatusCode))" "Green"
        } catch { Log "localhost:$port" "not responding" "Red" }
    }

    Write-Host ""
}

function Invoke-Bot {
    $taskName = "${TASK_PREFIX}WorkBot"
    $botFile  = "$PSScriptRoot\work-bot.ps1"
    $launcher = "$PSScriptRoot\work-bot-launcher.vbs"

    if ($Arg -eq "install") {
        $action   = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$launcher`""
        $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 0) -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settings -RunLevel Limited -Force | Out-Null
        Log "Telegram Bot" "installed - runs automatically at every login" "Green"
        Start-ScheduledTask -TaskName $taskName
        Log "Telegram Bot" "started now" "Green"

    } elseif ($Arg -eq "uninstall") {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Log "Telegram Bot" "startup task removed" "Red"

    } elseif ($Arg -eq "stop") {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Log "Telegram Bot" "stopped" "Red"

    } elseif ($Arg -eq "start") {
        Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Log "Telegram Bot" "started" "Green"

    } else {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Log "Telegram Bot" "installed (state: $($task.State))" "Yellow"
            Log "Telegram Bot" "use: work bot start / stop / uninstall" "DarkGray"
        } else {
            Log "Telegram Bot" "not installed - run: work bot install" "Yellow"
        }
    }
}

function Invoke-Open {
    if ($CHROME_TABS.Count -gt 0) {
        Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" -ArgumentList $CHROME_TABS
        Log "Chrome" "opened ($($CHROME_TABS.Count) tabs)" "Green"
    } else {
        Log "Chrome" "no CHROME_TABS configured in .env" "Yellow"
    }
    Write-Host ""
}

function Invoke-Morning {
    $taskName = "${TASK_PREFIX}MorningClaude"
    $launcher = "$PSScriptRoot\morning-claude-launcher.vbs"

    if ($Arg -eq "install") {
        $psArg  = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\work.ps1`" morning `"hello claude`""
        $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArg
        $trigger  = New-ScheduledTaskTrigger -Daily -At "05:30"
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Settings $settings -RunLevel Limited -Force | Out-Null
        Log "Morning Claude" "scheduled daily at 05:30 AM" "Green"

    } elseif ($Arg -eq "uninstall") {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Log "Morning Claude" "schedule removed" "Red"

    } elseif ($Arg -ne "") {
        # Run mode: called by the scheduled task with a message
        $msg = $Arg
        Log "Morning Claude" "asking Claude: $msg" "Cyan"
        Send-Telegram "Sending to Claude: $msg"
        try {
            $response = ($null | & $CLAUDE -p $msg 2>$null) | Out-String
            $response = ($response -replace '\x1b\[[0-9;]*[mK]', '').Trim()
            if ($response) { Send-Telegram "Claude says:`n`n$response" }
            else           { Send-Telegram "Claude did not respond." }
        } catch {
            Send-Telegram "Failed to reach Claude: $_"
        }

    } else {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) { Log "Morning Claude" "scheduled daily at 05:30 AM (state: $($task.State))" "Green" }
        else       { Log "Morning Claude" "not scheduled - run: work morning install" "Yellow" }
    }
}

function Invoke-Ask {
    $historyFile = "$PSScriptRoot\claude-chat-history.json"

    if ($Arg -eq "reset") {
        Remove-Item $historyFile -Force -ErrorAction SilentlyContinue
        Write-Host "  Conversation history cleared." -ForegroundColor Yellow
        return
    }

    if ($Arg -eq "") { Write-Host "  Usage: work ask <question>" -ForegroundColor Yellow; return }

    $history = @()
    if (Test-Path $historyFile) {
        try { $history = @(Get-Content $historyFile -Raw | ConvertFrom-Json) } catch {}
    }

    $context = ""
    if ($history.Count -gt 0) {
        $recent = $history | Select-Object -Last 10
        $context = "Here is our recent conversation for context:`n`n"
        foreach ($entry in $recent) {
            $context += "[You]: $($entry.question)`n[Claude]: $($entry.answer)`n`n"
        }
        $context += "Now answer this new question keeping the context above in mind:`n"
    }

    $fullPrompt = "$context$Arg"
    $response = ($null | & $CLAUDE -p $fullPrompt 2>$null) | Out-String
    $response = $response.Trim()
    Write-Host $response

    $history += [PSCustomObject]@{ question = $Arg; answer = $response }
    if ($history.Count -gt 50) { $history = $history | Select-Object -Last 50 }
    $history | ConvertTo-Json | Set-Content $historyFile -Encoding utf8
}

function Invoke-Config {
    $envFile = "$PSScriptRoot\.env"

    $fields = @(
        [PSCustomObject]@{ Key = "TELEGRAM_TOKEN";    Label = "Telegram Token";    Secret = $true  }
        [PSCustomObject]@{ Key = "TELEGRAM_CHAT_ID";  Label = "Telegram Chat ID";  Secret = $true  }
        [PSCustomObject]@{ Key = "CLAUDE_EXE";        Label = "Claude CLI Path";   Secret = $false }
        [PSCustomObject]@{ Key = "TASK_PREFIX";       Label = "Task Prefix";       Secret = $false }
        [PSCustomObject]@{ Key = "PROJECT_RUN";       Label = "Project Runner";    Secret = $false }
        [PSCustomObject]@{ Key = "PROJECT_WORKSPACE"; Label = "VS Code Workspace"; Secret = $false }
        [PSCustomObject]@{ Key = "CHROME_TABS";       Label = "Chrome Tabs";       Secret = $false }
        [PSCustomObject]@{ Key = "WSL_DISTRO";        Label = "WSL Distro";        Secret = $false }
        [PSCustomObject]@{ Key = "API_PORT";          Label = "API Port";          Secret = $false }
        [PSCustomObject]@{ Key = "FRONTEND_PORT";     Label = "Frontend Port";     Secret = $false }
        [PSCustomObject]@{ Key = "FRONTEND2_PORT";    Label = "Frontend 2 Port";   Secret = $false }
    )

    while ($true) {
        # reload values from file on each loop
        $values = @{}
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^([^#=][^=]*)=(.*)$') {
                $values[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }

        Clear-Host
        Write-Host ""
        Write-Host "  WorkPilot  |  Configuration" -ForegroundColor Cyan
        Write-Host "  =============================" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $fields.Count; $i++) {
            $f   = $fields[$i]
            $val = $values[$f.Key]
            $display = if ($f.Secret -and $val)    { "****" }
                       elseif ($val)                { $val  }
                       else                         { "(not set)" }
            $color = if ($val) { "White" } else { "DarkGray" }
            Write-Host ("  {0,2}.  {1,-22} {2}" -f ($i + 1), $f.Label, $display) -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "   0.  Exit" -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host "  Pick a number to edit").Trim()

        if ($choice -eq "0" -or $choice -eq "") { break }

        $idx = 0
        if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $fields.Count) {
            Write-Host "  Invalid choice." -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }

        $field   = $fields[$idx - 1]
        $current = $values[$field.Key]
        $displayCurrent = if ($field.Secret -and $current) { "****" } else { $current }

        Write-Host ""
        Write-Host "  Editing : $($field.Label)" -ForegroundColor Yellow
        if ($current) { Write-Host "  Current : $displayCurrent" -ForegroundColor DarkGray }
        $newVal = (Read-Host "  New value (Enter to keep current)").Trim()

        if ($newVal -ne "") {
            $content = Get-Content $envFile
            $written = $false
            $updated = $content | ForEach-Object {
                if ($_ -match "^$([regex]::Escape($field.Key))=") {
                    "$($field.Key)=$newVal"
                    $written = $true
                } else { $_ }
            }
            # if key didn't exist in file yet, append it
            if (-not $written) { $updated += "$($field.Key)=$newVal" }
            $updated | Set-Content $envFile -Encoding utf8
            Write-Host "  Saved!" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }

    Write-Host ""
    Write-Host "  Done. Restart the bot for changes to take effect:" -ForegroundColor DarkGray
    Write-Host "  work bot stop   then   work bot start" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-Update {
    $GITHUB_RAW   = "https://raw.githubusercontent.com/Skayologie/WorkPilot/main"
    $versionFile  = "$PSScriptRoot\VERSION"
    $localVersion = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.0.0" }

    Log "Update" "Current version : $localVersion" "Cyan"
    Log "Update" "Checking for updates..." "Yellow"

    try {
        $remoteVersion = (Invoke-WebRequest -Uri "$GITHUB_RAW/VERSION" -UseBasicParsing -TimeoutSec 10).Content.Trim()
    } catch {
        Log "Update" "Could not reach GitHub. Check your connection." "Red"
        return
    }

    if ($localVersion -eq $remoteVersion) {
        Log "Update" "Already up to date ($localVersion)." "Green"
        return
    }

    Log "Update" "New version available: $remoteVersion  (current: $localVersion)" "Yellow"
    Log "Update" "Downloading update..." "Yellow"

    $updateFiles = @("work.ps1","work-bot.ps1","work-bot-launcher.vbs","pilot.ps1","config.ps1",".gitignore","VERSION")
    $failed = 0
    foreach ($f in $updateFiles) {
        try {
            Invoke-WebRequest -Uri "$GITHUB_RAW/$f" -OutFile "$PSScriptRoot\$f" -UseBasicParsing -ErrorAction Stop
            Log "Update" "  OK  $f" "Green"
        } catch {
            Log "Update" "  FAIL  $f" "Red"
            $failed++
        }
    }

    if ($failed -eq 0) {
        Log "Update" "WorkPilot updated to $remoteVersion!" "Green"
        Log "Update" "Restart the bot for changes to take effect." "DarkGray"
        Send-Telegram "WorkPilot updated: $localVersion -> $remoteVersion. Restart the bot to apply changes."
    } else {
        Log "Update" "$failed file(s) failed. Update may be partial." "Red"
    }
}

function Show-Help {
    Write-Host ""
    Write-Host "  WorkPilot" -ForegroundColor Cyan
    Write-Host "  Usage: pilot <command> [arg]" -ForegroundColor White
    Write-Host ""
    Write-Host "  =============================" -ForegroundColor DarkGray
    Write-Host "  pilot begin                  Start apps + project services" -ForegroundColor Cyan
    Write-Host "  pilot done                   Stop apps + project services" -ForegroundColor Cyan
    Write-Host "  pilot status                 Show what is running" -ForegroundColor Cyan
    Write-Host "  pilot restart                Restart all project services" -ForegroundColor Cyan
    Write-Host "  pilot restart <service>      Restart one service" -ForegroundColor Cyan
    Write-Host "  pilot logs <service>         Tail service logs" -ForegroundColor Cyan
    Write-Host "  pilot doctor                 Full health check" -ForegroundColor Cyan
    Write-Host "  pilot open                   Open Chrome tabs only" -ForegroundColor Cyan
    Write-Host "  pilot ask <question>         Ask Claude anything" -ForegroundColor Cyan
    Write-Host "  pilot config                 Edit your .env settings" -ForegroundColor Cyan
    Write-Host "  pilot config show            Print current config" -ForegroundColor Cyan
    Write-Host "  pilot bot install            Install bot as auto-start task" -ForegroundColor Cyan
    Write-Host "  pilot bot start / stop       Start or stop the bot" -ForegroundColor Cyan
    Write-Host "  pilot morning install        Schedule daily 5:30 AM Claude greeting" -ForegroundColor Cyan
    Write-Host "  pilot update                 Check and install WorkPilot updates" -ForegroundColor Cyan
    Write-Host ""
}

switch ($Cmd) {
    "begin"   { Invoke-Begin }
    "done"    { Invoke-Done }
    "status"  { Invoke-Status }
    "restart" { Invoke-Restart }
    "logs"    { Invoke-Logs }
    "doctor"  { Invoke-Doctor }
    "open"    { Invoke-Open }
    "bot"     { Invoke-Bot }
    "morning" { Invoke-Morning }
    "ask"     { Invoke-Ask }
    "config"  { Invoke-Config }
    "update"  { Invoke-Update }
    "help"    { Show-Help }
    default   { Show-Help }
}
