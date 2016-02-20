@echo off
if "%1"=="" (
	echo "pass number (n) for amount of emus to run"
) else (
:: Launch the main program and don't continue until it completes (or is killed)
	2>nul (
	  echo N|start /wait "" cmd /c rerunEmus.bat %1
	)

	:: Cleanup up begins here
	taskkill /f /im EmuHawk.exe
)