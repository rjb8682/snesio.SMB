@echo off
cp configs\client.ini .\config.ini
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"