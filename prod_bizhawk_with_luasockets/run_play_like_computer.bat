@echo off
del config.ini
copy configs\play_like_computer.ini .\config.ini
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"