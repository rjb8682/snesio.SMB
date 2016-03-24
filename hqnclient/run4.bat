:: Kill all every 5 minutes, just in case something goes wrong.
:: TODO Increase this to a higher number. 5min is 4percent loss, 10min is 2percent
:: TODO This is obviously a band-aid. Fix the underlying problem.

start run.bat
start run.bat
start run.bat
start run.bat

:loop
timeout 300
taskkill /f /im hqnes.exe
goto loop