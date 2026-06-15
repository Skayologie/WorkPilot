# ==============================================================
#  WorkPilot - work-bot.ps1
#  Author  : Jawad Boulmal
#  GitHub  : https://github.com/Skayologie
#  Project : https://github.com/Skayologie/WorkPilot
# ==============================================================

. "$PSScriptRoot\config.ps1"

$TOKEN       = $env:TELEGRAM_TOKEN
$CHAT_ID     = $env:TELEGRAM_CHAT_ID
$WORK        = "$PSScriptRoot\work.ps1"
$TASK_PREFIX = if ($env:TASK_PREFIX) { $env:TASK_PREFIX } else { "MyWorkBot" }
$HIST_FILE   = "$PSScriptRoot\claude-chat-history.json"

# ---- first-run check ------------------------------------
if (-not $TOKEN -or $TOKEN -eq "YOUR_BOT_TOKEN_HERE") {
    Write-Host ""
    Write-Host "  SETUP REQUIRED" -ForegroundColor Yellow
    Write-Host "  Edit .env and set TELEGRAM_TOKEN and TELEGRAM_CHAT_ID" -ForegroundColor White
    Write-Host ""
    exit
}

# ---- helpers --------------------------------------------
function Send([string]$text) {
    $clean = ($text -replace '\x1b\[[0-9;]*[mK]', '').Trim()
    if ($clean.Length -gt 4000) { $clean = $clean.Substring(0, 4000) + "`n..." }
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$TOKEN/sendMessage" `
            -Method Post `
            -Body @{ chat_id = $CHAT_ID; text = $clean } | Out-Null
    } catch {}
}

function RunAsync([string]$cmd, [string]$arg = "") {
    $tmp = [System.IO.Path]::GetTempFileName()
    $job = Start-Job -ScriptBlock {
        param($w, $c, $a, $t)
        $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $w, $c)
        if ($a) { $psArgs += $a }
        & powershell @psArgs *>&1 | Out-File $t -Encoding utf8
    } -ArgumentList $WORK, $cmd, $arg, $tmp
    return [PSCustomObject]@{ Job = $job; TmpFile = $tmp }
}

# ---- startup --------------------------------------------
Write-Host "  WorkPilot Bot started. Waiting for commands..." -ForegroundColor Green

$offset = 0
try {
    $init = Invoke-RestMethod -Uri "https://api.telegram.org/bot$TOKEN/getUpdates" `
        -Method Post -Body @{ offset = -1; timeout = 0 } -TimeoutSec 5
    if ($init.result.Count -gt 0) { $offset = $init.result[-1].update_id + 1 }
} catch {}

Send "WorkPilot online. Send /help for all commands."
$jobs = [System.Collections.Generic.List[object]]::new()

# ---- main loop ------------------------------------------
while ($true) {
    $done = @($jobs | Where-Object { $_.Job.State -in "Completed","Failed","Stopped" })
    foreach ($item in $done) {
        $out   = Get-Content $item.TmpFile -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        $clean = ($out -replace '\x1b\[[0-9;]*[mK]', '').Trim()
        if ($clean) { Send $clean } else { Send "(no output received)" }
        Remove-Job  $item.Job     -Force -ErrorAction SilentlyContinue
        Remove-Item $item.TmpFile -Force -ErrorAction SilentlyContinue
        $jobs.Remove($item) | Out-Null
    }

    try {
        $res = Invoke-RestMethod `
            -Uri "https://api.telegram.org/bot$TOKEN/getUpdates" `
            -Method Post `
            -Body @{ offset = $offset; timeout = 5 } `
            -TimeoutSec 10

        foreach ($update in $res.result) {
            $offset = $update.update_id + 1
            $from   = "$($update.message.chat.id)"
            $text   = $update.message.text
            if ($from -ne "$CHAT_ID") { continue }

            Write-Host "  Received: $text" -ForegroundColor Cyan

            switch -Regex ($text) {

                "^/begin" {
                    Send "Starting work environment..."
                    $jobs.Add((RunAsync "begin"))
                }

                "^/done" {
                    Send "Stopping work environment..."
                    $jobs.Add((RunAsync "done"))
                }

                "^/status" {
                    Send "Fetching status..."
                    $jobs.Add((RunAsync "status"))
                }

                "^/doctor" {
                    Send "Running health check..."
                    $jobs.Add((RunAsync "doctor"))
                }

                "^/restart\s+(\S+)" {
                    $svc = $Matches[1]
                    Send "Restarting $svc..."
                    $jobs.Add((RunAsync "restart" $svc))
                }

                "^/restart" {
                    Send "Restarting all services..."
                    $jobs.Add((RunAsync "restart"))
                }

                "^/ask\s+(.+)" {
                    $question = $Matches[1].Trim()
                    Send "Asking Claude..."
                    $jobs.Add((RunAsync "ask" $question))
                }

                "^/ask$" {
                    Send "Usage: /ask your question here"
                }

                "^/reset" {
                    $jobs.Add((RunAsync "ask" "reset"))
                    Send "Conversation history cleared."
                }

                "^/history" {
                    if (-not (Test-Path $HIST_FILE)) {
                        Send "No conversation history yet."
                    } else {
                        try {
                            $h     = @(Get-Content $HIST_FILE -Raw | ConvertFrom-Json)
                            $last5 = $h | Select-Object -Last 5
                            $lines = $last5 | ForEach-Object {
                                $ans = $_.answer.Substring(0, [Math]::Min(120, $_.answer.Length))
                                "You: $($_.question)`nClaude: $ans..."
                            }
                            Send ("Last $($last5.Count) exchanges:`n`n" + ($lines -join "`n`n"))
                        } catch { Send "Could not read history." }
                    }
                }

                "^/schedule\s+(\d{1,2}:\d{2})(?:\s+(.+))?" {
                    $time = $Matches[1]
                    $msg  = if ($Matches[2]) { $Matches[2].Trim() } else { "hello claude" }
                    try {
                        $dt       = [datetime]::ParseExact($time, "H:mm", $null)
                        $taskName = "${TASK_PREFIX}Claude-" + $dt.ToString("HH-mm")
                        $safeMsg  = $msg -replace '"', "'"
                        $psArg    = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WORK`" morning `"$safeMsg`""
                        $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArg
                        $trigger  = New-ScheduledTaskTrigger -Daily -At $dt.ToString("HH:mm")
                        $settings = New-ScheduledTaskSettingsSet `
                                        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
                                        -StartWhenAvailable
                        Register-ScheduledTask -TaskName $taskName -Action $action `
                            -Trigger $trigger -Settings $settings -RunLevel Limited -Force | Out-Null
                        Send "Scheduled! Every day at $($dt.ToString('HH:mm')) Claude will be asked: `"$msg`""
                    } catch {
                        Send "Invalid time. Use: /schedule 08:30 Your message here"
                    }
                }

                "^/unschedule\s+(\d{1,2}:\d{2})" {
                    $time = $Matches[1]
                    try {
                        $dt       = [datetime]::ParseExact($time, "H:mm", $null)
                        $taskName = "${TASK_PREFIX}Claude-" + $dt.ToString("HH-mm")
                        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                        Send "Removed schedule at $($dt.ToString('HH:mm'))."
                    } catch {
                        Send "No schedule found for $time. Use /schedules to see all."
                    }
                }

                "^/schedules" {
                    $tasks = @(Get-ScheduledTask | Where-Object { $_.TaskName -like "${TASK_PREFIX}Claude-*" })
                    if ($tasks.Count -eq 0) {
                        Send "No schedules yet. Use /schedule HH:MM your message"
                    } else {
                        $lines = $tasks | ForEach-Object {
                            $t    = $_.TaskName -replace "${TASK_PREFIX}Claude-", "" -replace "-", ":"
                            $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                            $next = if ($info.NextRunTime) { $info.NextRunTime.ToString("dd/MM HH:mm") } else { "?" }
                            $arg  = $_.Actions[0].Arguments
                            $customMsg = if ($arg -match '"([^"]+)"$') { $Matches[1] } else { "hello claude" }
                            "- $t  |  `"$customMsg`"  (next: $next)"
                        }
                        Send ("Active schedules:`n" + ($lines -join "`n"))
                    }
                }

                "^/help" {
                    Send @"
Available commands:

Work environment:
/begin               Start everything
/done                Stop everything
/status              What is running
/restart             Restart all services
/restart <service>   Restart one service
/doctor              Full health check

Ask Claude:
/ask <question>      Ask Claude anything
/reset               Clear conversation history
/history             Show last 5 exchanges

Schedules:
/schedule 08:30 <message>   Add daily schedule
/unschedule 08:30           Remove a schedule
/schedules                  List all schedules
"@
                }

                default {
                    Send "Unknown command. Send /help for the list."
                }
            }
        }
    } catch {
        Start-Sleep -Seconds 3
    }
}
