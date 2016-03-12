local socket = require("socket")

-- TODO: new client config?
RUN_LOCAL = false

function getClientCode()
	-- TODO: should we write the file for easier debugging?
	local client, err = socket.connect("snes.bluefile.org", 56666)
	if not client then
		print("Could not reach facilitator: " .. err)
		return nil
	end

	client:send("client\n")
	response, err = client:receive()
	client:close()

	if not response then
		print("Facilitator failed: " .. err)
		return nil
	end

	return loadstring(response)
end

local clientCode = nil
if RUN_LOCAL then
	print("Running locally")
	clientCode = require("client_logic")
else
	clientCode = getClientCode()
end

if not clientCode then
	print("Could not load client. Exiting BizHawk")
	client.exit()
	return
end

while true do
	clientCode()
end
