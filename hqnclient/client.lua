local socket = require("socket")

function getClientCode()
	local client, err = socket.connect("snes.bluefile.org", 56666)
	if not client then
		print("Could not reach facilitator: " .. err)
		return nil
	end
	client:send("client\n")
	response, err = client:receive("*a")
	client:close()
	if not response then
		print("Facilitator failed: " .. err)
		return nil
	end
	result, err = loadstring(response)
	if not result then
		print("Error loading code: " .. err)
		return nil
	end
	return result
end

clientCode = getClientCode()

if not clientCode then
	print("Could not load client. Exiting BizHawk")
	client.exit()
	return
end

clientCode()