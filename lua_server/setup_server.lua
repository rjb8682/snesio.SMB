local socket = require("socket")
local serpent = require("serpent")

function getServerConfig()
	local client, err = socket.connect("snes.bluefile.org", 56666)
	assert(client, "Could not reach facilitator: " .. tostring(err))
	client:send("server\n")
	response, err = client:receive("*a")
	client:close()
	assert(response, err)
	ok, result = serpent.load(response, {comment=false})
	assert(result, ok)
	return result
end

local config = getServerConfig()

print("Asserting...")
assert(config.Name)
assert(config.VERSION_CODE)
assert(config.Population)
print("Done!")

print("Creating experiment: " .. config.Name)
io.popen("mkdir -p current/genomes/", "r")

-- Wait for the file to write
socket.sleep(3)

local file = io.output("current/config")
file:write(serpent.dump(config))
file:close()
print("lua dumber_server.lua current 2> err.txt to start the experiment")
