@echo off

del config.ini
copy configs\demo_projector.ini .\config.ini

start "EmuHawk.exe" "%~dp0\EmuHawk.exe"