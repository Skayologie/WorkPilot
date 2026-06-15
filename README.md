# WorkPilot

Control your entire work environment from the terminal — or from your phone via Telegram.

**Author:** Jawad Boulmal — [github.com/Skayologie](https://github.com/Skayologie)

---

## What is WorkPilot?

WorkPilot is a personal work environment manager for Windows. One command starts everything you need for your day: Docker, VS Code, Chrome tabs, Slack, and your project services. One command stops it all. And a Telegram bot lets you control everything from your phone.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Windows 10 / 11 | PowerShell 5.1+ included |
| [Claude CLI](https://claude.ai/download) | For `/ask` and morning messages |
| Telegram account | To create the bot via @BotFather |
| Git (optional) | Only needed if you clone manually |

---

## Installation

### One-liner (recommended)

Open PowerShell as your normal user (not Administrator) and run:

```powershell
irm https://www.jawadboulmal.com/workpilot/install.ps1 | iex
```

The installer will:
1. Download all files to `C:\workpilot`
2. Ask for your Telegram token and Chat ID
3. Ask for optional settings (Chrome tabs, project paths, ports)
4. Add `C:\workpilot` to your PATH
5. Register the Telegram bot to auto-start at every login

Open a **new terminal** after installation and type `work help`.

---

### Manual installation

```powershell
# 1. Clone the repo
git clone https://github.com/Skayologie/WorkPilot.git C:\workpilot

# 2. Copy the example config
Copy-Item C:\workpilot\.env.example C:\workpilot\.env

# 3. Edit your config
work config

# 4. Add to PATH (run once)
$p = [System.Environment]::GetEnvironmentVariable("PATH","User")
[System.Environment]::SetEnvironmentVariable("PATH","$p;C:\workpilot","User")

# 5. Install the Telegram bot auto-start
work bot install
```

---

## Configuration

All settings live in one file: `C:\workpilot\.env`

Edit it interactively from the terminal:

```powershell
work config
```

This opens a numbered menu:

```
  WorkPilot  |  Configuration
  =============================

   1.  Telegram Token         ****
   2.  Telegram Chat ID       ****
   3.  Claude CLI Path        C:\Users\you\.local\bin\claude.exe
   4.  Task Prefix            WorkPilot
   5.  Project Runner         D:\MyProject\bin\run.ps1
   6.  VS Code Workspace      D:\MyProject.code-workspace
   7.  Chrome Tabs            https://gmail.com|https://github.com
   8.  WSL Distro             Ubuntu
   9.  API Port               3000
  10.  Frontend Port          4200
  11.  Frontend 2 Port

   0.  Exit

  Pick a number to edit: _
```

Pick a number, type the new value, press Enter. Done.

### Getting your Telegram credentials

**Bot Token:**
1. Open Telegram and message `@BotFather`
2. Send `/newbot` and follow the steps
3. Copy the token it gives you

**Chat ID:**
1. Message your new bot anything (e.g. `hello`)
2. Open `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates` in your browser
3. Find `"chat":{"id": 123456789}` — that number is your Chat ID

---

## Terminal commands

```
work begin                  Start everything (Docker, VS Code, Chrome, Slack, services)
work done                   Stop everything and close all apps
work status                 Show what is currently running
work restart                Restart all project services
work restart <service>      Restart one specific service
work logs <service>         Tail logs for a service
work doctor                 Full health check (apps, WSL, Docker, ports)
work open                   Open Chrome tabs only
work ask <question>         Ask Claude anything (with conversation memory)
work config                 Edit settings interactively
work config show            Print current config (tokens hidden)
work bot install            Register bot as Windows auto-start task
work bot start              Start the Telegram bot manually
work bot stop               Stop the Telegram bot
work morning install        Schedule a daily 5:30 AM Claude greeting
work morning uninstall      Remove the morning schedule
work help                   Show all commands
```

---

## Telegram bot commands

Once the bot is running, send these from your phone:

```
/begin               Start work environment
/done                Stop everything
/status              What is running
/restart             Restart all services
/restart <service>   Restart one service
/doctor              Full health check

/ask <question>      Ask Claude anything
/reset               Clear Claude conversation history
/history             Show last 5 Claude exchanges

/schedule 08:30 <message>   Add a daily Claude schedule
/unschedule 08:30           Remove a schedule
/schedules                  List all active schedules

/help                Show all commands
```

---

## Project structure

```
C:\workpilot\
  work.ps1                  Main script — all commands live here
  work-bot.ps1              Telegram bot loop
  work-bot-launcher.vbs     Launches bot silently at login (no console window)
  work.bat                  CLI entry point — lets you type "work" in any terminal
  config.ps1                Loads .env into process environment variables
  install.ps1               One-liner installer script
  .env                      Your personal config — never commit this
  .env.example              Safe template for sharing/backup
  .gitignore                Excludes .env and chat history from git
```

---

## How the bot auto-starts

When you run `work bot install`, WorkPilot registers a Windows Scheduled Task that triggers at every login. It uses a VBScript launcher (`work-bot-launcher.vbs`) to start the bot completely hidden — no terminal window, no tray icon. The bot runs silently in the background.

To verify it is running:
```powershell
work bot status
```

---

## Updating

```powershell
cd C:\workpilot
git pull
```

Your `.env` is never touched by updates.

---

## Uninstalling

```powershell
# Remove the bot auto-start task
work bot uninstall

# Remove the morning schedule (if installed)
work morning uninstall

# Remove from PATH and delete files
$p = [System.Environment]::GetEnvironmentVariable("PATH","User")
[System.Environment]::SetEnvironmentVariable("PATH",($p -replace ";C:\\workpilot",""),"User")
Remove-Item C:\workpilot -Recurse -Force
```

---

## License

MIT — free to use, modify, and share.
