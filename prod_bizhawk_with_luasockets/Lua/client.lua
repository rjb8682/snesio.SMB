local socket = require("socket")
local SERVER_IP = "127.0.0.1" -- "129.21.252.86"

-- find out which port the OS chose for us
--local ip, port = client:getsockname()
-- print a message informing what's up
--print("port: " .. port)
--print("After connecting, you have 100s to enter a line to be echoed")

function mysplit(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t={}; i=1
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		t[i] = str
		i = i + 1
	end
	return t
end

function playGame(stateId, ai)
	for i = 1, 10 do
		emu.frameadvance()
	end
	return stateId
end

-- loop forever waiting for clients
while true do
	emu.frameadvance()

	-- connect to server
	client, err = socket.connect(SERVER_IP, 56506)
	if not err then
		--print("connecting to: " .. client:getpeername())
		client:settimeout(1000000)

		--print("Sending request...")
		bytes, err = client:send("request\n")
		if not err then
			--print("Bytes: " .. bytes)
		else
			--print("Request error: " .. err)
		end


		--print("Waiting for response...")
		response, err2 = client:receive()
		if not err2 then
			print("Response: " .. response)
			-- Close the client and play
			client:close()

			toks = mysplit(response, "!")
			stateId = tonumber(toks[1])
			iterationId = tonumber(toks[2])
			ai = toks[3]

			local fitness = playGame(stateId, ai)

			-- Send it back yo
			client, err = socket.connect(SERVER_IP, 56506)
			if not err then
				bytes, err = client:send("results!" .. stateId .. "!" .. iterationId .. "!" .. fitness .. "\n")
				client:close()
			end

		else
			print("Response error: " .. err2)
		end
	else
		print(err)
	end

	-- done with client, close the object
	if client then client:close() end
end