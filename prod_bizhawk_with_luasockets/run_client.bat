@echo off
del config.ini
copy configs\client.ini .\config.ini
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"