local serpent = require("serpent")
local socket = require("socket")

-- Increment this when breaking changes are made (will cause old clients to be ignored)
local VERSION_CODE = 9

function initConfigFile()
	-- Set default config file state here
	config = {
		clientId = "default_name",
		server = "snes.bluefile.org",
		port = 56506,
		demoFile = "",
		drawGui = false,
		debug = false,
		killEvery = 900
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

	-- Set defaults if missing
	if not config.clientId then
		config.clientId = "default_name"
	end
	if not config.server then
		config.server = "snes.bluefile.org"
	end
	if not config.killEvery then
		config.killEvery = 900
	end

	-- If clientId set to "hostname", do a DNS lookup
	if config.clientId == "hostname" then
		local hostname = socket.dns.gethostname()
		if hostname then
			-- Limit to 12 chars
			config.clientId = string.sub(socket.dns.gethostname(), 1, 12)
		end
	end
end
loadConfigFile()

print("Client: " .. config.clientId)
print("Server: " .. config.server .. ":" .. config.port)

----------------- INPUTS ----------------------------
Filename = "1.State"
ButtonNames = {
	"A",
	--"B",
	--"Up",
	--"Down",
	"Left",
	"Right",
}

BoxRadiusX = 6 -- 6, 6, 2, 0
BoxRadiusY = 6
ShiftX = 2
ShiftY = 2
InputSize = (BoxRadiusX*2+1)*(BoxRadiusY*2+1)
Inputs = InputSize + 3 -- marioVX, marioVY, BIAS NEURON
Outputs = #ButtonNames

-- How many pixels away (manhattan distance) to check for an enemy
EnemyTolerance = 8

-- Tile types
BOTTOM_TILE = 84
BRICK = 82
COIN = 194

ENEMY_TYPES = 0x0016

-- Enemy types
LIFT_START = 0x24
LIFT_END = 0x2C
TRAMPOLINE = 0x32

-- (shouldn't be conflicting with real enemy types)
HAMMER_TYPE = 0x0abc0af

-- Hammers
HAMMER_STATUS_START = 0x002A
HAMMER_STATUS_END = 0x0032
HAMMER_HITBOXES = 0x04D0
----------------- END INPUTS ----------------------------

ProgressTimeoutConstant = 420	-- 7 seconds
FreezeTimeoutConstant   = 60	-- 1 second

MaxNodes = 1000000

wonLevel = false

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

	marioCurX = memory.readbyte(0x0086)
	marioCurY = memory.readbyte(0x03B8)
	marioVX = memory.read_s8(0x0057)
	marioVY = memory.read_s8(0x009F)

	marioWorld = memory.read_s8(0x075F)
	marioLevel = memory.read_s8(0x0760)

	screenX = memory.readbyte(0x03AD)
	screenY = memory.readbyte(0x03B8)

	-- print("marioCurX: " .. marioCurX .. " marioCurY: " .. marioCurY)
	-- print("marioX: " .. marioX .. " marioY: " .. marioY)
	-- print("screenX: " .. screenX .. " screenY: " .. screenY)
end

function getTile(dx, dy)
	local x = marioX + dx + 8
	local y = marioY + dy - 16
	local page = math.floor(x/256)%2

	local subx = math.floor((x%256)/16)
	local suby = math.floor((y - 32)/16)
	local addr = 0x500 + page*13*16+suby*16+subx
	
	if suby >= 13 or suby < 0 then
		return 0
	end
	
	tile = memory.readbyte(addr)
	-- Don't let Mario see coins.
	if tile ~= 0 and tile ~= COIN then
		--print(tostring(x) .. ", " .. tostring(y) .. ": " .. tostring(memory.readbyte(addr)))
		return 1
	else
		return 0
	end
end

function getSprites()
	--print("-----sprites--------")
	local sprites = {}
	for slot=0,4 do -- TODO SHOULDNT THIS BE 5?!
		local enemy = memory.readbyte(0xF+slot)
		local enemyType = memory.readbyte(ENEMY_TYPES + slot)
		if enemy ~= 0 then
			local ex = memory.readbyte(0x6E + slot)*0x100 + memory.readbyte(0x87+slot)
			local ey = memory.readbyte(0xCF + slot)+24
			--print(enemyType .. ": " .. ex .. ", " .. ey)
			sprites[#sprites+1] = {x=ex,y=ey,t=enemyType}
		end
	end
	--print("------hammers-------")
	for addr=HAMMER_STATUS_START,HAMMER_STATUS_END do
		local hammerSlot = memory.readbyte(addr)
		-- Is this hammer active?
		if hammerSlot ~= 0 then
			hammerAddr = HAMMER_HITBOXES + 4 * (addr - HAMMER_STATUS_START)
			--print("slot: " .. hammerSlot .. " addr: " .. hammerAddr)
			-- Take the center of the hitbox
			local cx = (memory.readbyte(hammerAddr + 0)
				      + memory.readbyte(hammerAddr + 2) + 0.5) / 2
			local cy = (memory.readbyte(hammerAddr + 1) +
				        memory.readbyte(hammerAddr + 3) + 0.5) / 2
			--print(hammerSlot .. ": " .. (cx - marioCurX) .. ", " .. (cy - marioCurY))
			sprites[#sprites+1] = {x=cx,y=cy,t=HAMMER_TYPE}
		end
	end
	
	return sprites
end

function getInputs()
	getPositions()
	sprites = getSprites()
	local inputs = {}

	YStart = -(BoxRadiusY-ShiftY)*16
	YEnd =    (BoxRadiusY+ShiftY)*16
	XStart = -(BoxRadiusX-ShiftX)*16
	XEnd =    (BoxRadiusX+ShiftX)*16
	
	for dy=YStart,YEnd,16 do
		for dx=XStart,XEnd,16 do
			inputs[#inputs+1] = 0
			
			--print("dx: " .. dx .. " dy: " .. dy)
			for i = 1,#sprites do
				-- Lifts are sprites, but not enemies. Make them a 1.
				-- TODO: Trampolines??
				if sprites[i].t == HAMMER_TYPE then
					-- Hammers are relative on the screen, but use an axis starting at 0
					distx = math.abs(sprites[i].x - screenX - (dx-8)) -- was 8
					disty = math.abs(sprites[i].y - screenY - (dy-8)) -- was 8
					--print("H -> x: " .. sprites[i].x .. " y: " .. sprites[i].y .. " distx: " .. distx .. " disty: " .. disty)
				else
					-- Otherwise, calculate relative to start of level
					distx = math.abs(sprites[i].x - (marioX+dx-8))
					disty = math.abs(sprites[i].y - (marioY+dy-8))
					--print("* -> distx: " .. distx .. " disty: " .. disty)
				end
				if distx <= EnemyTolerance and disty <= EnemyTolerance then
					if sprites[i].t >= LIFT_START and sprites[i].t < LIFT_END then
						inputs[#inputs] = 1
					else
						inputs[#inputs] = -1
					end
				end
			end

			-- Write tiles AFTER sprites, so that vines don't show up
			-- on top of pipes even when they're inside.
			-- This means that hammer bros jumping are briefly not shown
			tile = getTile(dx, dy)
			if tile == 1 and marioY+dy < 0x1B0 then
				inputs[#inputs] = 1
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
	table.insert(inputs, 1) -- BIAS NEURON

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

	controller["P1 B"] = true

	joypad.set(controller)
end

function playGame(stateIndex, network)
	savestate.load(stateIndex .. ".State")

	-- Reset state
	clearJoypad()
	local progressTimeout = ProgressTimeoutConstant
	local freezeTimeout = FreezeTimeoutConstant
	local rightmost = 0
	local currentFrame = 0
	marioX = nil
	marioY = nil

	-- Play until we die / win
	while true do
		-- Decide which inputs to set
		if currentFrame%4 == 0 then
			evaluateCurrent(network)
		end
		joypad.set(controller)

		-- Check how far we are in the level
		if marioX > rightmost then
			rightmost = marioX
			progressTimeout = ProgressTimeoutConstant
		end

		if oldMarioX ~= marioX or oldMarioY ~= marioY then
			freezeTimeout = FreezeTimeoutConstant
		end

		local fitness = rightmost - (currentFrame / 4)

		if config.drawGui == true then
			gui.drawBox(0, 7, 300, 40, 0xD0FFFFFF, 0xD0FFFFFF)
			gui.drawText(0, 10, "Generation: " .. generation
								.. "." .. currentSpecies
								.. "." .. currentGenome
								.. " Fitness: " .. math.floor(fitness), 0xFF000000, 11)
			local world, level = getWorldAndLevel(stateIndex)
			gui.drawText(0, 22, "Level: " .. world .. "-" .. level .. " (" .. stateIndex .. ")", 0xFF000000, 11)
			gui.drawText(120, 22, "Total Max: " .. maxFitness, 0xFF000000, 11)
		end

		-- Check for death
		if playerState == 6 or playerState == 0x0B or verticalScreenPosition > 1 then
			local reason = "enemyDeath"
			if verticalScreenPosition > 1 then reason = "fell" end
			if config.debug then console.writeline(reason) end
			return rightmost, currentFrame, 0, reason, stateIndex
		end

		-- Did we win? (set in getPositions)
		if wonLevel then
			wonLevel = false
			if config.debug then console.writeline("victory") end
			return rightmost, currentFrame, 1, "victory", stateIndex
		end

		-- Check for freeze timeout
		freezeTimeout = freezeTimeout - 1
		if freezeTimeout <= 0 or fitness < -100 then
			if config.debug then console.writeline("freeze") end
			return rightmost, currentFrame, 0, "freeze", stateIndex
		end

		-- Check for progress timeout
		progressTimeout = progressTimeout - 1
		if progressTimeout <= 0 or fitness < -100 then
			if config.debug then console.writeline("noProgress") end
			return rightmost, currentFrame, 0, "noProgress", stateIndex
		end
		
		-- Advance frame since we didn't win / die
		currentFrame = currentFrame + 1
		emu.frameadvance()

		if config.drawGui then
			displayGenome(network)
		end
	end
end

function loadNetwork(filename)
	local file = io.open(filename, "r")
	local ok, network = serpent.load(file:read("*line"))
	file:close()
	return network
end

function displayGenome(network)
	local cells = {}
	local i = 1
	local cell = {}
	for dy=-BoxRadiusY,BoxRadiusY do
		for dx=-BoxRadiusX,BoxRadiusX do
			cell = {}
			cell.x = 50+5*dx
			cell.y = 70+5*dy
			cell.value = network.neurons[i].value
			cells[i] = cell
			i = i + 1
		end
	end
	
	gui.drawBox(50-BoxRadiusX*5-3,70-BoxRadiusY*5-3,50+BoxRadiusX*5+2,70+BoxRadiusY*5+2,0xFF000000, 0x80808080)
	for n,cell in pairs(cells) do
		if n > Inputs or cell.value ~= 0 then
			local color = math.floor((cell.value+1)/2*256)
			if color > 255 then color = 255 end
			if color < 0 then color = 0 end
			local opacity = 0xFF000000
			if cell.value == 0 then
				opacity = 0x50000000
			end
			color = opacity + color*0x10000 + color*0x100 + color
			gui.drawBox(cell.x-2,cell.y-2,cell.x+2,cell.y+2,opacity,color)
		end
	end
	
	local XChange = ShiftX * 6
	local YChange = ShiftY * 5
	gui.drawBox(49-XChange,72-YChange,55-XChange,78-YChange,0x00000000,0x80FF0000)
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
	percentage = "666" -- I hate globals...
	currentGenome = config.demoFile
	currentSpecies = config.demoFile
	generation = config.demoFile
	maxFitness = 0
	z = 1
	while true do
		-- Avoid castles and water levels
		if z % 4 ~= 0 and z ~= 6 and z ~= 26 then
			maxFitness = maxFitness + calculateDemoFitness(playGame(z, loadNetwork(config.demoFile)))
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

-- Global so that we can re-use the network string when possible
networkStr = nil

-- Controls when to stop training
timeToDie = false

start_time = socket.gettime()

local response = nil

-- loop forever waiting for games to play
while true do
	emu.frameadvance()

	local toks, iterationId, ok

	-- If the server responded with the next genome from the previous iteration,
	-- then use that rather than asking for another genome.
	if nextResponseToUse then
		if config.debug then print("using next genome from two-way connection") end
		response = nextResponseToUse
		nextResponseToUse = nil
	else
		-- Connect to server
		local client, err = socket.connect(config.server, config.port)
		if not err then
			bytes, err = client:send(config.clientId .. "\n")
			response, err2 = client:receive()
		end
		-- Close the client and play
		if client then
			client:close()
		end
	end

	if response then
		toks = mysplit(response, "!")
		response = nil -- Delete response so we don't re-play the level

		-- Is the server too busy for us?
		if toks[1] == "wait" then
			timeout = tonumber(toks[2])
			console.writeline(socket.gettime() .. " sleeping for " .. timeout)
			socket.sleep(timeout)
		else
			-- Otherwise, play a level!
			ok, levels = serpent.load(toks[1])
			iterationId = toks[2]
			generation = toks[3]
			currentSpecies = toks[4]
			currentGenome = toks[5]
			maxFitness = toks[6]
			percentage = toks[7]
			networkStr = toks[8]

			-- Play all requested levels
			for stateId, level in pairs(levels) do
				if level.a then
					-- Ensure the network is fresh by re-loading it from the string
					-- TODO: explore ways to reset it robustly?
					local ok, network = serpent.load(networkStr)
					local dist, frames, wonLevel, reason = playGame(stateId, network)
					if config.debug then print("level: " .. stateId .. " distance: " .. dist .. " frames: " .. frames .. " reason: " .. reason) end
					level.d = dist
					level.f = frames
					level.w = wonLevel
					level.r = reason
				end
			end

			-- Done playing. Determine if we should kill the emulator.
			timeToDie = socket.gettime() - start_time > config.killEvery

			-- Send it back yo
			-- TODO just put it all in levels table
			local results_to_send = config.clientId .. "!"
					.. generation .. "!"
					.. currentSpecies .. "!"
					.. currentGenome .. "!"
					.. iterationId .. "!" 
					.. VERSION_CODE .. "!"
				    .. serpent.dump(levels) .. "!"
				    .. tostring(timeToDie) .. "\n"

			local client2, err2 = socket.connect(config.server, config.port)
			if not err2 then
				client2:send(results_to_send)

				-- Only try to receive results if we're not going to kill ourselves
				if not timeToDie then
					-- The server might send the next level right away
					maybeResponse, err3 = client2:receive()
					-- TODO: delte this and make the client loop simpler. The server never sends no level any more
					if not err3 and response ~= "no_level" then
						if config.debug then print("received next level from two-way connection") end
						nextResponseToUse = maybeResponse
					end
				end
			end
			if client2 then
				client2:close()
			end
		end
	else
		print("No response.")
		if err then
			print("err: " .. err)
		end
		if err2 then
			print("err2: " .. err2)
		end
	end

	-- Time do die?
	if timeToDie then
		client.exit()
	end

    collectgarbage()
end
