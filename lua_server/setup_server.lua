local socket = require("socket")
local serpent = require("serpent")

function getServerConfig()
	local client, err = socket.connect("snes.bluefile.org", 56666)
	assert(client, "Could not reach facilitator: " .. tostring(err))
	client:send("server\n")
	response, err = client:receive("*a")
	client:close()
	assert(response, err)
	ok, result = serpent.load(response)
	assert(result, ok)
	return result
end

config = getServerConfig()
assert(config, "Could not load config")
print(serpent.block(config))

print("Creating experiment: " .. config.Name)
io.popen("mkdir -p current/genomes", "r")
local file, err = io.open("current/config", "w")
assert(file, err)
file:write(serpent.dump(config))
file:close()
print("lua dumber_server.lua current 2> err.txt to start the experiment")
