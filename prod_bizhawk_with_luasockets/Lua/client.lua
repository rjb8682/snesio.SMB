local serpent = require("serpent")
local socket = require("socket")
local SERVER_IP = "129.21.252.86"

-- random state (need to prune)

Filename = "1.State"
ButtonNames = {
	"A",
	--"B",
	--"Up",
	--"Down",
	"Left",
	"Right",
}

BoxRadius = 6
InputSize = (BoxRadius*2+1)*(BoxRadius*2+1) -- marioVX, marioVY

Inputs = InputSize + 4
Outputs = #ButtonNames

compoundDistanceTraveled = 0

Population = 300
DeltaDisjoint = 2.0
DeltaWeights = 0.4
DeltaThreshold = 1.0

StaleSpecies = 15

MutateConnectionsChance = 0.25
PerturbChance = 0.90
CrossoverChance = 0.75
LinkMutationChance = 2.0
NodeMutationChance = 0.50
BiasMutationChance = 0.40
StepSize = 0.1
DisableMutationChance = 0.4
EnableMutationChance = 0.2

TimeoutConstant = 20

MaxNodes = 1000000

wonLevel = false

-- random state (need to prune)

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

function getPositions()
	if gameinfo.getromname() == "Super Mario Bros." then
		marioX = memory.readbyte(0x6D) * 0x100 + memory.readbyte(0x86)
		marioY = memory.readbyte(0x03B8)+16

		playerFloatState = memory.readbyte(0x1D)
		if playerFloatState == 3 then
			wonLevel = true
		end
		playerState = memory.readbyte(0x000E)

		verticalScreenPosition = memory.readbyte(0x00B5)

		-- New inputs!!
		marioCurX = memory.read_s8(0x0086)
		marioCurY = memory.read_s8(0x03B8)
		marioVX = memory.read_s8(0x0057)
		marioVY = memory.read_s8(0x009F)

		marioWorld = memory.read_s8(0x075F)
		marioLevel = memory.read_s8(0x0760)

		--console.writeline("vx " .. marioVX)
		--console.writeline("vy " .. marioVY)
		-- New inputs!!
	
		screenX = memory.readbyte(0x03AD)
		screenY = memory.readbyte(0x03B8)
	end
end

function getTile(dx, dy)
	if gameinfo.getromname() == "Super Mario Bros." then
		local x = marioX + dx + 8
		local y = marioY + dy - 16
		local page = math.floor(x/256)%2

		local subx = math.floor((x%256)/16)
		local suby = math.floor((y - 32)/16)
		local addr = 0x500 + page*13*16+suby*16+subx
		
		if suby >= 13 or suby < 0 then
			return 0
		end
		
		if memory.readbyte(addr) ~= 0 then
			return 1
		else
			return 0
		end
	end
end

function getSprites()
	if gameinfo.getromname() == "Super Mario Bros." then
		local sprites = {}
		for slot=0,4 do
			local enemy = memory.readbyte(0xF+slot)
			if enemy ~= 0 then
				local ex = memory.readbyte(0x6E + slot)*0x100 + memory.readbyte(0x87+slot)
				local ey = memory.readbyte(0xCF + slot)+24
				sprites[#sprites+1] = {["x"]=ex,["y"]=ey}
			end
		end
		
		return sprites
	end
end

function getExtendedSprites()
	if gameinfo.getromname() == "Super Mario Bros." then
		return {}
	end
end

function getInputs()
	getPositions()
	
	sprites = getSprites()
	extended = getExtendedSprites()
	
	local inputs = {}
	
	for dy=-BoxRadius*16,BoxRadius*16,16 do
		for dx=-BoxRadius*16,BoxRadius*16,16 do
			inputs[#inputs+1] = 0
			
			tile = getTile(dx, dy)
			if tile == 1 and marioY+dy < 0x1B0 then
				inputs[#inputs] = 1
			end
			
			for i = 1,#sprites do
				distx = math.abs(sprites[i]["x"] - (marioX+dx))
				disty = math.abs(sprites[i]["y"] - (marioY+dy))
				if distx <= 8 and disty <= 8 then
					inputs[#inputs] = -1
				end
			end

			for i = 1,#extended do
				distx = math.abs(extended[i]["x"] - (marioX+dx))
				disty = math.abs(extended[i]["y"] - (marioY+dy))
				if distx < 8 and disty < 8 then
					inputs[#inputs] = -1
				end
			end
		end
	end

	inputs[#inputs+1] = marioCurY
	inputs[#inputs+1] = marioVX
	inputs[#inputs+1] = marioVY
	
	return inputs
end

function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end

function evaluateNetwork(network, inputs)
	table.insert(inputs, 1)

	if #inputs ~= Inputs then
		console.writeline("Incorrect number of neural network inputs.")
		console.writeline(#inputs)
		console.writeline(Inputs)
		return {}
	end
	
	for i=1,Inputs do
		network.neurons[i].value = inputs[i]
	end
	
	for _,neuron in pairs(network.neurons) do
		local sum = 0
		for j = 1,#neuron.incoming do
			local incoming = neuron.incoming[j]
			local other = network.neurons[incoming.into]
			sum = sum + incoming.weight * other.value
		end
		
		if #neuron.incoming > 0 then
			neuron.value = sigmoid(sum)
		end
	end
	
	local outputs = {}
	for o=1,Outputs do
		local button = "P1 " .. ButtonNames[o]
		if network.neurons[MaxNodes+o].value > 0 then
			outputs[button] = true
		else
			outputs[button] = false
		end
	end
	
	return outputs
end

function clearJoypad()
	controller = {}
	for b = 1,#ButtonNames do
		controller["P1 " .. ButtonNames[b]] = false
	end
	joypad.set(controller)
end

function evaluateCurrent(network)
	inputs = getInputs()
	controller = evaluateNetwork(network, inputs)
	
	if controller["P1 Left"] and controller["P1 Right"] then
		controller["P1 Left"] = false
		controller["P1 Right"] = false
	end

	--if controller["P1 Up"] and controller["P1 Down"] then
	--	controller["P1 Up"] = false
	--	controller["P1 Down"] = false
	--end

	controller["P1 B"] = true

	joypad.set(controller)
end

function playGame(stateName, network)
	currentFrame = 0
	savestate.load(stateName)
	timeout = TimeoutConstant
	rightmost = 0

	-- Play until we die / win
	while true do
		-- Decide which inputs to set
		if currentFrame%4 == 0 then
			evaluateCurrent(network)
		end

		-- Check how far we are in the level
		getPositions()
		if marioX > rightmost then
			rightmost = marioX
			compoundDistanceTraveled = rightmost
			timeout = TimeoutConstant
		end

		local distanceFitness = compoundDistanceTraveled 
		local timeFitnessPenalty = currentFrame / 4
		local fitness = distanceFitness - timeFitnessPenalty

		-- Check for death
		if playerState == 6 or playerState == 0x0B or verticalScreenPosition > 1 then
			console.writeline("Player Died")
			return distanceFitness - timeFitnessPenalty
		end

		-- Did we win? (set in getPositions)
		if wonLevel then
			wonLevel = false
			return 10000 - timeFitnessPenalty
		end

		-- Did we time out?
		timeout = timeout - 1
		local timeoutBonus = currentFrame / 4
		if timeout + timeoutBonus <= 0  then
			compoundDistanceTraveled = 0
			return distanceFitness - timeFitnessPenalty
		end

		-- TODO wtf is this (main loop)
		--[[
		local measured = 0
		local total = 0
		for _,species in pairs(pool.species) do
			for _,genome in pairs(species.genomes) do
				total = total + 1
				if genome.fitness ~= 0 then
					measured = measured + 1
				end
			end
		end
		-- TODO wtf is this
		]]--
		
		-- Advance frame since we didn't win / die
		currentFrame = currentFrame + 1
		emu.frameadvance()
	end
end

-- loop forever waiting for games to play
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
			--print("Response: " .. response)
			-- Close the client and play
			client:close()

			toks = mysplit(response, "!")
			stateId = toks[1]
			iterationId = tonumber(toks[2])
			ok, network = serpent.load(toks[3])

			-- TODO: validate inputs before using them!!
			if not toks and stateId and ok and network then
				-- TODO bail out
			end

			local fitness = playGame(stateId .. ".State", network)
			print("level: " .. stateId .. " fitness: " .. fitness)

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