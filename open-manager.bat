@echo off

cd /d %~dp0

powershell.exe -ExecutionPolicy Bypass -File ".\manage-blog.ps1"

pause