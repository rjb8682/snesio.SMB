@echo off
del config.ini
copy configs\demo.ini .\config.ini
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"