local bitser = require("bitser")
local binser = require("binser")
if #arg == 0 then
	print("usage: luajit bitser_to_binser file")
	return
end

local bitserFile = io.open(arg[1], "rb")
local str = bitserFile:read("*a")
assert(str)
local bits = bitser.loads(str)
assert(bits)
assert(bits.network)
bitserFile:close()
binser.writeFile(arg[1] .. "binser", bits)
