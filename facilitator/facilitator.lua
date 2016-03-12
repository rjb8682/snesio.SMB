local serpent = require("serpent")
local socket = require("socket")
local port = 56666
local server = assert(socket.bind("*", port))
local ip, port = server:getsockname()

-- TODO: System to determine current active experiment
-- maybe servers check in with facilitator? idk
local currentExperiment = "default.experiment"

function mysplit(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t={} ; i=1
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		t[i] = str
		i = i + 1
	end
	return t
end

function getClientCode(filename)
	file = io.open("codebase/" .. filename, "r")
	code = file:read("*all")
	file:close()
	return code
end

function getExperiment(experiment_name)
	file = io.open("experiments/" .. experiment_name, "r")
	experiment = file:read("*all")
	file:close()
	-- Compact-ify (experiment format is pretty-printed)
	ok, tab = serpent.load(experiment)
	if ok then
		return tab
	end
	return nil
end

while true do
	-- Receive the line
	local client = server:accept()
	local line, err = client:receive()
	if line then
		print("received: " .. line)
		toks = mysplit(line)
		if toks[1] == "client" then
			print("hello, client!")
			local experiment = getExperiment(currentExperiment)
			local code_file = experiment.ClientCode
			-- TODO: change from "client_logic" to based on code_file
			client:send(getClientCode("client_logic.lua"))
		elseif toks[1] == "server" then
			print("hello, server!")
			local experiment = getExperiment(currentExperiment)
			local result = serpent.dump(experiment)
			print(result)
			client:send(result)
		end

		-- done with client, close the object
		client:close()
	end
end
