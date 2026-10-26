@echo off
rem Starts the COD Zombies server (Minecraft PS4) in WSL (Ubuntu) - double-click it. Ctrl+C, or typing "stop", saves the world and
rem stops it; "help" lists the console's commands. See start.sh for what's in this folder.
title COD Zombies server
cd /d "%~dp0"
for /f "delims=" %%p in ('wsl -d Ubuntu -u root -- wslpath -a "%~dp0start.sh"') do set "SH=%%p"
wsl -d Ubuntu -u root -- bash "%SH%"
pause
