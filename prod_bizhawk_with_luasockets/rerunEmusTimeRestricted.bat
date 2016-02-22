@echo off
setlocal enableextensions enabledelayedexpansion
set originalAmount=%1
set numEmus=%1
:loop
:forloop
if %numEmus% leq 0 goto end

:timeloop
set tm=%time%
set hh=!tm:~0,2!
set mm=!tm:~3,2!
if !hh! lss 18 (
    echo "After 10pm -- good to go!"
) else (
    if !hh! geq 22 (
        echo "Before 6pm -- good to go!"
    ) else (
	    echo "Within 6pm-10pm; not running"
	    @timeout /t 60
	    goto timeloop
	)
)

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