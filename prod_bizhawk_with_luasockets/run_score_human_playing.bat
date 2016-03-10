@echo off
cp configs\score_human_playing.ini .\config.ini
start "EmuHawk.exe" "%~dp0\EmuHawk.exe"