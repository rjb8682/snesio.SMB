@echo off
set originalAmount=%1
set numEmus=%1
:loop
:forloop
if %numEmus% leq 0 goto end
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"
set /A numEmus=numEmus-1
@timeout /t 1 
goto forloop
:end
set /A numEmus=originalAmount
@timeout /t 300
taskkill /f /im EmuHawk.exe
@timeout /t 1 
goto loop