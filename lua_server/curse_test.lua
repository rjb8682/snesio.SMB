local curses = require("curses")
curses.initscr()
curses.cbreak()
curses.echo(false)
curses.nl(false)
local stdscr = curses.stdscr()
stdscr:clear()

while true do
	stdscr:mvaddstr(0,0,'testing\ntesting\ntesting\ntesting\n')
	stdscr:refresh()
end
