@echo off

cd /d %~dp0

powershell.exe -ExecutionPolicy Bypass -File ".\publish-blog.ps1"

pause