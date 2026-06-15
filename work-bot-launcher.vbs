' WorkPilot - work-bot-launcher.vbs
' Author  : Jawad Boulmal
' GitHub  : https://github.com/Skayologie
Dim scriptDir
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & scriptDir & "work-bot.ps1""", 0, False
