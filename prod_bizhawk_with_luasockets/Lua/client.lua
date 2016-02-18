local serpent = require("serpent")
local socket = require("socket")
local SERVER_IP = "129.21.64.237"

-- Increment this when breaking changes are made (will cause old clients to be ignored)
local VERSION_CODE = 3

function initConfigFile()
	-- Set default config file state here
	config = {
		clientId = "default_client",
		server = SERVER_IP,
		demoFile = "",
		drawGui = true
	}
	local file = io.open("config.txt", "w")
	file:write(serpent.dump(config))
	file:close()
end
function loadConfigFile()
	local file = io.open("config.txt", "r")
	if not file then
		print("couldn't open config file, creating default")
		initConfigFile()
	else
		ok, config = serpent.load(file:read("*line"))
		file:close()
		if not ok then
			print("bad config file, creating default")
			initConfigFile()
		end
	end
end
loadConfigFile()

if config.server then
	print("Using " .. config.server)
	SERVER_IP = config.server
end

-- Uncomment this to play in demo mode! Make sure this filename exists in the same dir as the client.lua.
--DEMO_FILE = "backup_network.fitness17920.3.gen1.genome7.species68.NEW_BEST"

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

Inputs = InputSize + 3
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

ProgressTimeoutConstant = 420	-- 7 seconds
FreezeTimeoutConstant   = 60	-- 1 second

MaxNodes = 1000000

wonLevel = false

-- random state (need to prune)

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
		oldMarioX = marioX
		oldMarioY = marioY
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

	inputs[#inputs+1] = marioVX
	inputs[#inputs+1] = marioVY
	
	return inputs
end

function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end

function evaluateNetwork(network, inputs)
	table.insert(inputs, 1) -- wtf is this?

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

function playGame(stateIndex, network)
	local currentFrame = 0
	savestate.load(stateIndex .. ".State")
	local progressTimeout = ProgressTimeoutConstant
	local freezeTimeout = FreezeTimeoutConstant
	local rightmost = 0

	-- Play until we die / win
	while true do
		-- Decide which inputs to set
		if currentFrame%4 == 0 then
			evaluateCurrent(network)
		end
		joypad.set(controller)

		-- Check how far we are in the level
		getPositions()
		if marioX > rightmost then
			rightmost = marioX
			compoundDistanceTraveled = rightmost
			progressTimeout = ProgressTimeoutConstant
		end

		if oldMarioX ~= marioX or oldMarioY ~= marioY then
			freezeTimeout = FreezeTimeoutConstant
		end

		fitness = compoundDistanceTraveled - (currentFrame / 4)

		if config.drawGui == true then
			gui.drawBox(0, 7, 300, 40, 0xD0FFFFFF, 0xD0FFFFFF)
			gui.drawText(0, 10, "Gen " .. generation
								.. " Species " .. currentSpecies
								.. " Genome " .. currentGenome
								.. " " .. percentage, 0xFF000000, 11)
			gui.drawText(0, 22, "Fitness: " .. math.floor(fitness), 0xFF000000, 11)
			gui.drawText(120, 22, "Total Max: " .. maxFitness, 0xFF000000, 11)
		end

		-- Check for death
		if playerState == 6 or playerState == 0x0B or verticalScreenPosition > 1 then
			console.writeline("Player Died")
			local reason = "enemyDeath"
			if verticalScreenPosition > 1 then reason = "fell" end
			return compoundDistanceTraveled, currentFrame, 0, reason, stateIndex
		end

		-- Did we win? (set in getPositions)
		if wonLevel then
			wonLevel = false
			return compoundDistanceTraveled, currentFrame, 1, "victory", stateIndex
		end

		-- Check for freeze timeout
		freezeTimeout = freezeTimeout - 1
		if freezeTimeout <= 0 or fitness < -100 then
			compoundDistanceTraveled = 0
			return compoundDistanceTraveled, currentFrame, 0, "freeze", stateIndex
		end

		-- Check for progress timeout
		progressTimeout = progressTimeout - 1
		if progressTimeout <= 0 or fitness < -100 then
			compoundDistanceTraveled = 0
			return compoundDistanceTraveled, currentFrame, 0, "noProgress", stateIndex
		end
		
		-- Advance frame since we didn't win / die
		currentFrame = currentFrame + 1
		emu.frameadvance()
	end
end

function loadNetwork(filename)
	local file = io.open(filename, "r")
	local ok, network = serpent.load(file:read("*line"))
	file:close()
	return network
end

------------------------ DEMO CODE ONLY -------------------------------------
WorldAugmenter = 0.2
LevelAugmenter = 0.1
function getWorldAndLevel(i)
	local world = math.floor((i - 1) / 4) + 1
	local level = ((i - 1) % 4) + 1
	return world, level
end

function calculateDemoFitness(distance, frames, wonLevel, reason, stateIndex)
	local result = distance
	local timePenalty = frames / 10
	if wonLevel == 1 then
		result = result + 5000
	end

	local world, level = getWorldAndLevel(stateIndex)
	local multi = 1.0 + (WorldAugmenter*world) + (LevelAugmenter*level)

	return 100 + (multi * result) - timePenalty
end

-- Play demo mode if set (see top of file)
if config.demoFile and config.demoFile ~= "" then
	local demoNetwork = loadNetwork(config.demoFile)
	percentage = "666" -- I hate globals...
	currentGenome = config.demoFile
	currentSpecies = config.demoFile
	generation = config.demoFile
	maxFitness = 0
	z = 1
	while true do
		-- Avoid castles and water levels
		if z % 4 ~= 0 and z ~= 6 and z ~= 26 then
			maxFitness = maxFitness + calculateDemoFitness(playGame(z, demoNetwork))
		end

		z = z + 1
		if z == 33 then
			print("Total max fitness: " .. maxFitness)
			maxFitness = 0
			z = 1
		end
	end
end
-------------------- END DEMO CODE ONLY -------------------------------------



-- loop forever waiting for games to play
while true do
	emu.frameadvance()

	local toks, stateId, iterationId, ok, network, fitness

	-- connect to server
	local client, err = socket.connect(SERVER_IP, 56506)
	if not err then
		client:settimeout(10000)

		bytes, err = client:send("request!" .. config.clientId .. "\n")

		response, err2 = client:receive()
		if not err2 then
			-- Close the client and play
			client:close()

			toks = mysplit(response, "!")
			stateId = toks[1]
			iterationId = toks[2]
			generation = toks[3]
			currentSpecies = toks[4]
			currentGenome = toks[5]
			maxFitness = toks[6]
			percentage = toks[7]
			ok, network = serpent.load(toks[8])

			local dist, frames, wonLevel, reason = playGame(stateId, network)
			print("level: " .. stateId .. " distance: " .. dist .. " frames: " .. frames .. " reason: " .. reason)

			-- Send it back yo
			local results_to_send = "results!" .. stateId .. "!"
					.. iterationId .. "!" 
				    .. dist .. "!"
				    .. frames .. "!"
				    .. wonLevel .. "!"
				    .. reason .. "!"
				    .. VERSION_CODE .. "!"
				    .. config.clientId .. "\n"
			local client2, err2 = socket.connect(SERVER_IP, 56506)
			if not err2 then
				client2:send(results_to_send)
				client2:close()
			end
		else
			print("Response err2: " .. err2)
		end
	else
		print("Response err: " .. err)
	end

	-- done with client, close the object
	if client then client:close() end
	if client2 then client2:close() end
	collectgarbage()
end
