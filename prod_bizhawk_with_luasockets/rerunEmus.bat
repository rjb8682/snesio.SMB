@echo off
set numEmus=%1
:loop
:forloop
if %numEmus% leq 0 goto end
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"
set /A numEmus=numEmus-1
@timeout /t 1 
goto forloop
:end
@timeout /t 60
taskkill /f /im EmuHawk.exe
@timeout /t 1 
goto loop