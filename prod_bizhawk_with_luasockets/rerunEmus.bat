@echo off
setlocal ENABLEDELAYEDEXPANSION
set originalAmount=%1
:loop
::set /A totalEmus=tasklist | find /I /C "EmuHawk.exe"
for /f "tokens=1,*" %%a in ('tasklist ^| find /I /C "EmuHawk.exe"') do set totalEmus=%%a
if !totalEmus! geq %originalAmount% goto end
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"
@timeout /t 3
goto loop
:end
@timeout /t 3
goto loop