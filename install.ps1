# ==============================================================
#  WorkPilot - install.ps1
#  Author  : Jawad Boulmal
#  GitHub  : https://github.com/Skayologie
#  Project : https://github.com/Skayologie/WorkPilot
# --------------------------------------------------------------
#  Usage: irm https://www.jawadboulmal.com/workpilot/install.ps1 | iex
# ==============================================================

$GITHUB_RAW  = "https://raw.githubusercontent.com/Skayologie/WorkPilot/main"
$INSTALL_DIR = "C:\workpilot"
$FILES = @(
    "work.ps1",
    "work-bot.ps1",
    "work-bot-launcher.vbs",
    "work.bat",
    "config.ps1",
    ".env.example",
    ".gitignore",
    "VERSION"
)

Clear-Host
Write-Host ""
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host "   WorkPilot Installer" -ForegroundColor Cyan
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host ""

# --- create install directory
if (-not (Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
}
Write-Host "  Install directory: $INSTALL_DIR" -ForegroundColor DarkGray
Write-Host ""

# --- download files
Write-Host "  Downloading files from GitHub..." -ForegroundColor Yellow
Write-Host ""
$failed = 0
foreach ($file in $FILES) {
    $dest = Join-Path $INSTALL_DIR $file
    try {
        Invoke-WebRequest -Uri "$GITHUB_RAW/$file" -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Write-Host "    OK  $file" -ForegroundColor Green
    } catch {
        Write-Host "    FAIL  $file" -ForegroundColor Red
        $failed++
    }
}
if ($failed -gt 0) {
    Write-Host ""
    Write-Host "  $failed file(s) failed to download. Check your internet or GitHub repo." -ForegroundColor Red
    exit 1
}

# --- setup .env
Write-Host ""
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host "   Configuration" -ForegroundColor Cyan
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host ""

$envFile = Join-Path $INSTALL_DIR ".env"
if (Test-Path $envFile) {
    Write-Host "  .env already exists — skipping config (delete it to reconfigure)" -ForegroundColor DarkGray
} else {
    Write-Host "  You need a Telegram bot. Message @BotFather on Telegram to create one." -ForegroundColor White
    Write-Host ""

    $token = ""
    while (-not $token) {
        $token = (Read-Host "  Telegram Bot Token").Trim()
    }

    $chatId = ""
    while (-not $chatId) {
        $chatId = (Read-Host "  Telegram Chat ID  (message your bot then check /getUpdates)").Trim()
    }

    # auto-detect claude
    $claudeAuto = (Get-Command claude -ErrorAction SilentlyContinue)
    if ($claudeAuto) {
        $claudePath = $claudeAuto.Source
        Write-Host "  Claude CLI found: $claudePath" -ForegroundColor Green
    } else {
        Write-Host "  Claude CLI not found in PATH." -ForegroundColor Yellow
        $claudePath = (Read-Host "  Claude CLI full path (e.g. C:\Users\YOU\.local\bin\claude.exe)").Trim()
    }

    Write-Host ""
    Write-Host "  Optional — press Enter to skip any of these:" -ForegroundColor DarkGray
    Write-Host ""
    $projectRun  = (Read-Host "  Project runner script (e.g. D:\MyProject\bin\run.ps1)").Trim()
    $workspace   = (Read-Host "  VS Code workspace file (e.g. D:\MyProject.code-workspace)").Trim()
    $chromeTabs  = (Read-Host "  Chrome tabs on begin, pipe-separated (e.g. https://gmail.com|https://github.com)").Trim()
    $wslDistro   = (Read-Host "  WSL distro name for Docker (default: Ubuntu)").Trim()
    $apiPort     = (Read-Host "  API port to health-check (default: 3000)").Trim()
    $taskPrefix  = (Read-Host "  Task prefix for scheduler (default: MyWorkBot)").Trim()

    if (-not $wslDistro)  { $wslDistro  = "Ubuntu" }
    if (-not $apiPort)    { $apiPort    = "3000" }
    if (-not $taskPrefix) { $taskPrefix = "MyWorkBot" }

    @"
# Telegram Bot
TELEGRAM_TOKEN=$token
TELEGRAM_CHAT_ID=$chatId

# Claude CLI
CLAUDE_EXE=$claudePath

# Task scheduler prefix (no spaces)
TASK_PREFIX=$taskPrefix

# Project (optional)
PROJECT_RUN=$projectRun
PROJECT_WORKSPACE=$workspace

# Chrome tabs to open on work begin (pipe-separated)
CHROME_TABS=$chromeTabs

# WSL distro for Docker health checks
WSL_DISTRO=$wslDistro

# Service ports to health-check
API_PORT=$apiPort
FRONTEND_PORT=
FRONTEND2_PORT=
"@ | Set-Content $envFile -Encoding utf8

    Write-Host ""
    Write-Host "  .env created." -ForegroundColor Green
}

# --- add install dir to user PATH
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$INSTALL_DIR*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$userPath;$INSTALL_DIR", "User")
    Write-Host "  Added $INSTALL_DIR to PATH." -ForegroundColor Green
} else {
    Write-Host "  PATH already contains $INSTALL_DIR." -ForegroundColor DarkGray
}

# --- install telegram bot as auto-start task
Write-Host ""
Write-Host "  Installing Telegram bot (auto-starts at login)..." -ForegroundColor Yellow
powershell -NoProfile -ExecutionPolicy Bypass -File "$INSTALL_DIR\work.ps1" bot install

# --- done
Write-Host ""
Write-Host "  =================================" -ForegroundColor Green
Write-Host "   WorkPilot is ready!" -ForegroundColor Green
Write-Host "  =================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Open a NEW terminal and type:" -ForegroundColor White
Write-Host ""
Write-Host "    work begin       start your work environment" -ForegroundColor Cyan
Write-Host "    work done        stop everything" -ForegroundColor Cyan
Write-Host "    work status      see what is running" -ForegroundColor Cyan
Write-Host "    work help        all commands" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Your Telegram bot is live. Send /help to it now." -ForegroundColor White
Write-Host ""
