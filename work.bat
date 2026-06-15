@echo off
:: WorkPilot - work.bat
:: Author  : Jawad Boulmal
:: GitHub  : https://github.com/Skayologie
start "" powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0work.ps1" %*
exit
