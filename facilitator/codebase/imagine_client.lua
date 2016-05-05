local serpent = require("serpent")
local zmq = require("zmq")
local binser = require("binser")
local socket = require("socket")

require("hqnes")
emu.loadrom("smb.nes")
gui.enable()
--gui.setfullscreen(true)

local SCALE = 3

gui.setscale(SCALE)
gui.settitle("Imagine RIT")
emu.setframerate(61)

-- We need randomness to ensure clients aren't identical
math.randomseed(socket.gettime())
math.random()
math.random()

local memory = memory or mainmemory
local joypad = joypad
local emu = emu
local savestate = savestate

local frameCount = 0
local startTime = socket.gettime()


-- Controls when to stop training
local timeToDie = false

-- Increment this when breaking changes are made (will cause old clients to be ignored)
local VERSION_CODE = "IMAGINE"

function initConfigFile()
	-- Set default config file state here
	config = {
		clientId = "hostname",
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
			config.clientId = hostname
		end
	end
end
loadConfigFile()
config.port = 56509

print("Client: " .. config.clientId)
print("Server: " .. config.server .. ":" .. config.port)
print("Version code: " .. VERSION_CODE)

----------------- INPUTS ----------------------------
Filename = "1.State"
ButtonNames = {
	"a",
	--"B",
	--"Up",
	--"Down",
	"left",
	"right",
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
FLAGPOLE = 37

ENEMY_TYPES = 0x0016

-- Enemy types
LIFT_START = 0x24
LIFT_END = 0x2C
TRAMPOLINE = 0x32
PIRANHA = 0x0D

COIN_SPRITE = 666

-- (shouldn't be conflicting with real enemy types)
HAMMER_TYPE = 0x0abc0af

-- Hammers
HAMMER_STATUS_START = 0x002A
HAMMER_STATUS_END = 0x0032
HAMMER_HITBOXES = 0x04D0

-- Mario's max/min velocities in x and y
local MAX_X_VEL =  40
local MIN_X_VEL = -40
local MAX_Y_VEL =   4
local MIN_Y_VEL =  -5

----------------- END INPUTS ----------------------------

ProgressTimeoutConstant = 420	-- 7 seconds
FreezeTimeoutConstant   = 60	-- 1 second

MaxNodes = 1000000

wonLevel = false

-- Normalize to [-1, 1]
function normalize(z, min, max)
	return (2 * (z - min) / (max - min)) - 1
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
	marioVX = normalize(memory.read_s8(0x0057), MIN_X_VEL, MAX_X_VEL)
	marioVY = normalize(memory.read_s8(0x009F), MIN_Y_VEL, MAX_Y_VEL)

	-- TODO: add player vertical fractional velocity (0x0433)

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
	if tile ~= 0 and tile ~= COIN and tile ~= FLAGPOLE then
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
			local ex = memory.readbyte(0x6E + slot)*0x100 + memory.readbyte(0x87+slot) - 8
			local ey = memory.readbyte(0xCF + slot)+24
			--print(enemyType .. ": " .. ex .. ", " .. ey)

			if enemyType >= LIFT_START and enemyType <= LIFT_END then
				if marioWorld < 4 then
 					-- Triple-wide platforms
 					sprites[#sprites+1] = {x=ex+32,y=ey-12,t=enemyType}
					sprites[#sprites+1] = {x=ex+0, y=ey-12,t=enemyType}
					sprites[#sprites+1] = {x=ex+16,y=ey-12,t=enemyType}
				else
	 				-- Double-wide platforms
	 				sprites[#sprites+1] = {x=ex+8,y=ey-12,t=enemyType}
					sprites[#sprites+1] = {x=ex+16,y=ey-12,t=enemyType}
					sprites[#sprites+1] = {x=ex-0,y=ey-12,t=enemyType}
				end
			elseif enemyType == PIRANHA then
				-- print("plant")
				sprites[#sprites+1] = {x=ex-8,y=ey-8,t=PIRANHA}
				sprites[#sprites+1] = {x=ex+8,y=ey-8,t=PIRANHA}
				sprites[#sprites+1] = {x=ex-8,y=ey-0,t=PIRANHA}
				sprites[#sprites+1] = {x=ex+8,y=ey-0,t=PIRANHA}
			else
				sprites[#sprites+1] = {x=ex,y=ey,t=enemyType}
			end
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

local TWIDTH = 16
local YStart = -(BoxRadiusY-ShiftY)*TWIDTH
local YEnd =    (BoxRadiusY+ShiftY)*TWIDTH
local XStart = -(BoxRadiusX-ShiftX)*TWIDTH
local XEnd =    (BoxRadiusX+ShiftX)*TWIDTH

function getInputs()
	getPositions()
	local sprites = getSprites()
	local inputs = {}
	
	for dy=YStart,YEnd,TWIDTH do
		for dx=XStart,XEnd,TWIDTH do
			inputs[#inputs+1] = 0
			
			--print("dx: " .. dx .. " dy: " .. dy)
			for i = 1,#sprites do
				-- Lifts are sprites, but not enemies. Make them a 1.
				-- TODO: Trampolines??
				local sprite = sprites[i]
				if sprite.t == HAMMER_TYPE then
					-- Hammers are relative on the screen, but use an axis starting at 0
					distx = math.abs(sprite.x - screenX - (dx-8)) -- was 8
					disty = math.abs(sprite.y - screenY - (dy-8)) -- was 8
					--print("H -> x: " .. sprites[i].x .. " y: " .. sprites[i].y .. " distx: " .. distx .. " disty: " .. disty)
				else
					-- Otherwise, calculate relative to start of level
					distx = math.abs(sprite.x - (marioX+dx-7.5))
					disty = math.abs(sprite.y - (marioY+dy-7.5))
					--print("* -> distx: " .. distx .. " disty: " .. disty)
				end
				-- if cartesian(distx, disty) <= EnemyTolerance then
				-- if manhattan(distx, disty) <= EnemyTolerance then
				if distx <= EnemyTolerance and disty <= EnemyTolerance then
					if sprite.t >= LIFT_START and sprite.t <= LIFT_END
						or sprite.t == TRAMPOLINE then
						inputs[#inputs] = 1
					elseif sprite.t == COIN_SPRITE then
						inputs[#inputs] = 0
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

local function sigmoid(x)
    return 2/(1+math.exp(-4.9*x))-1
end

function evaluateNetwork(network, inputs)
	table.insert(inputs, 1) -- BIAS NEURON

	if #inputs ~= Inputs then
		print("Incorrect number of neural network inputs.")
		print(#inputs)
		print(Inputs)
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
			-- Sigmoid
			neuron.value = 2/(1+math.exp(-4.9*sum))-1
		end
	end
	
	local outputs = {}
	for o=1,Outputs do
		local button = ButtonNames[o]
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
		controller[ButtonNames[b]] = false
	end
	joypad.set(controller)
end

function evaluateCurrent(network)
	inputs = getInputs()
	controller = evaluateNetwork(network, inputs)
	
	if controller["left"] and controller["right"] then
		controller["left"] = false
		controller["right"] = false
	end

	controller["b"] = true

	joypad.set(controller)
end

function playGame(stateIndex, genome)
    local network = genome.network
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

		-- Check for death
		if playerState == 6 or playerState == 0x0B or verticalScreenPosition > 1 then
			local reason = "enemyDeath"
			if verticalScreenPosition > 1 then reason = "fell" end
			if config.debug then print(reason) end
			return rightmost, currentFrame, 0, reason, stateIndex
		end

		-- Did we win? (set in getPositions)
		if wonLevel then
			wonLevel = false
			if config.debug then print("victory") end
			return rightmost, currentFrame, 1, "victory", stateIndex
		end

		-- Check for freeze timeout
		freezeTimeout = freezeTimeout - 1
		if freezeTimeout <= 0 or fitness < -100 then
			if config.debug then print("freeze") end
			return rightmost, currentFrame, 0, "freeze", stateIndex
		end

		-- Check for progress timeout
		progressTimeout = progressTimeout - 1
		if progressTimeout <= 0 or fitness < -100 then
			if config.debug then print("noProgress") end
			return rightmost, currentFrame, 0, "noProgress", stateIndex
		end
		
		-- Advance frame since we didn't win / die
		currentFrame = currentFrame + 1
		emu.frameadvance()
		frameCount = frameCount + 1

		if gui.isenabled() and config.drawGui then
			displayGenome(genome)
		end
	end
end

function loadNetwork(filename)
	local file = io.open(filename, "r")
	local ok, network = serpent.load(file:read("*line"))
	file:close()
	return network
end

function displayGenome(genome)
    gui.clear()
    local network = genome.network
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

    local dxCell = {}
    dxCell.x = 80
    dxCell.y = 110
    dxCell.value = network.neurons[Inputs-2].value
    cells[Inputs-2] = dxCell
    text(65, 108, "vx",   0xCCCCCCCC, 10 * SCALE)
	
    local dyCell = {}
    dyCell.x = 80
    dyCell.y = 120
    dyCell.value = network.neurons[Inputs-1].value
    cells[Inputs-1] = dyCell
    text(65, 118, "vy",   0xCCCCCCCC, 10 * SCALE)

    local biasCell = {}
    biasCell.x = 80
    biasCell.y = 130
    biasCell.value = network.neurons[Inputs].value
    cells[Inputs] = biasCell
    text(65, 128, "bias", 0xCCCCCCCC, 10 * SCALE)

    for n, neuron in pairs(network.neurons) do
        cell = {}
        if n > Inputs and n <= MaxNodes then
            cell.x = 140
            cell.y = 100
            cell.value = neuron.value
            cells[n] = cell
        end
    end

    for n=1, 4 do
        for _,gene in pairs(genome.genes) do
            if gene.enabled then
                local c1 = cells[gene.into]
                local c2 = cells[gene.out]
                if c1 and c2 then
                    if gene.into > Inputs and gene.into <= MaxNodes then
                        c1.x = 0.75 * c1.x + 0.25 * c2.x + 30
                        if c1.x >= c2.x then
                            c1.x = c1.x - 70
                        end

                        if c1.x < 90 then
                            c1.x = 90
                        end
                        if c1.x > 210 then
                            c1.x = 210
                        end
                        c1.y = 0.75 * c1.y + 0.25 * c2.y - 2
                    end

                    if gene.out > Inputs and gene.out <= MaxNodes then
                        c2.x = 0.75 * c1.x + 0.25 * c2.x + 60
                        if c1.x >= c2.x then -- TODO C2?
                            c2.x = c1.x - 70
                        end

                        if c2.x < 90 then
                            c2.x = 90
                        end
                        if c2.x > 210 then
                            c2.x = 210
                        end
                        c2.y = 0.75 * c1.y + 0.25 * c2.y - 2
                    end
                end
            end
        end
    end

    -- Button labels
    for o = 1, Outputs do
        cell = {}
        cell.x = 220
        cell.y = 46 + 8 * o
        cell.value = network.neurons[MaxNodes + o].value
        cells[MaxNodes+o] = cell
        local color
        if cell.value > 0 then
            color = 0xFF0000FF
        else
            color = 0xFF000000
        end
        text(226, 44 + 8*o, ButtonNames[o], color, 10 * SCALE)
    end

    -- Box background
	box(50-BoxRadiusX*5-3,70-BoxRadiusY*5-3,50+BoxRadiusX*5+2,70+BoxRadiusY*5+2,0x000000FF, 0xFFFFFFAA)

    -- Draw neuron boxes
	for n,cell in pairs(cells) do
		if n > Inputs or cell.value ~= 0 then
			local color = math.floor((cell.value+1)/2*256)
			if color > 255 then color = 255 end
			if color < 0 then color = 0 end
			local opacity = 0x000000FF
			if cell.value == 0 then
				opacity = 0x00000055
			end
			local color = color*0x1000000 + color*0x10000 + color * 0x100 + opacity
			box(cell.x-2,cell.y-2,cell.x+2,cell.y+2,color,color)
		end
	end


    -- Draw neuron connections
    for _, gene in pairs(genome.genes) do
        if gene.enabled then
            local c1 = cells[gene.into]
            local c2 = cells[gene.out]
            local opacity = 0x000000B5
            if c1 and c2 then
                if c1.value == 0 then
                    opacity = 0x00000055
                end
                
                local color = red_to_green(gene.weight, opacity)
                line(c1.x+1, c1.y, c2.x-3, c2.y, color)
            end
        end
    end

	-- Mario!
	local XChange = ShiftX * 6
	local YChange = ShiftY * 5
	box(50-XChange,73-YChange,54-XChange,77-YChange,0x0000AAF0,0x0000AAF0)
end

-- Interpolates a weight (from -1 to +1) to red <-> green
function red_to_green(weight, opacity)
    local power = sigmoid(weight) + 1.0
    local red, green, blue
    blue = 0.0
    if power < 0 then
        green = 1.0
        red = 2 * power
    else
        red = 1.0
        green = 1.0 - 2 * (power-0.5)
    end
    
    local color = bit.band(0xFF000000, bit.lshift(red, 24)) +
                  bit.band(0x00FF0000, bit.lshift(green, 16)) +
                  bit.band(0x0000FF00, bit.lshift(blue, 8)) +
                  bit.band(0x000000FF, opacity)
    return color
end

-- ARGB to RGBA
function fix_color(color)
    -- Get alpha in bottom bytes
    a = bit.band(0x000000FF, bit.rshift(color, 24))
    -- Move rgb to top bytes
    rgb = bit.band(0xFFFFFF00, bit.lshift(color, 8))
    rgba = bit.band(rgb, a)
    return rgba
end

function text(x, y, text, color, fontsize)
    gui.drawText(x * SCALE, y * SCALE, text, color, fontsize * SCALE)
end

function line(x1, y1, x2, y2, color)
    x1 = x1 * SCALE
    y1 = y1 * SCALE
    x2 = x2 * SCALE
    y2 = y2 * SCALE
    gui.drawLine(x1, y1, x2, y2, color)
end

function box(x1, y1, x2, y2, border, fill)
    x1 = x1 * SCALE
    y1 = y1 * SCALE
    x2 = x2 * SCALE
    y2 = y2 * SCALE
    gui.drawRectangle(x1, y1, math.abs(x2 - x1), math.abs(y1 - y2), border, fill)
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
	local maxFitness = 0
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

local function checkForServerOrderedDeath(resp)
	-- Kill ourselves if the server says so
	if resp and resp == "die" then
		timeToDie = true
	end
end

-- Global so that we can re-use the network string when possible
networkStr = nil

start_time = socket.gettime()

local ctx = zmq.init(1)
local client = ctx:socket(zmq.REQ)
client:setopt(zmq.LINGER, 100) -- Wait 100ms to send remaining messages before closing
client:connect("tcp://" .. config.server .. ":" .. tostring(config.port))

local response = nil

-- loop forever waiting for games to play
while true do
	-- If the server responded with the next genome from the previous iteration,
	-- then use that rather than asking for another genome.
	if nextResponseToUse then
		if config.debug then print("using next genome from two-way connection") end
		response = nextResponseToUse
		nextResponseToUse = nil
	else
		-- Connect to server
		local start = socket.gettime()
		-- TODO necessary?
		if client then
			bytes, err = client:send(binser.serialize({clientId = config.clientId}), zmq.NOBLOCK)
			response, err2 = client:recv()
			checkForServerOrderedDeath(response)
		end
		print("time: " .. socket.gettime() - start)
	end

	if response then
		local start = socket.gettime()
		local bits = binser.deserializeN(response, 1)
		response = nil -- Delete response so we don't re-play the level

		-- Play some levels!
		local levels = assert(bits.levels)
		local generation = assert(bits.generation)
		local currentSpecies = assert(bits.species)
		local currentGenome = assert(bits.genome)
		local networkStr = assert(bits.networkStr)

		-- Play all requested levels
		for stateId, level in pairs(levels) do
			if level.a then
				-- Ensure the network is fresh by re-loading it from the string
				-- TODO: explore ways to reset it robustly?
				local genome = assert(binser.deserializeN(networkStr, 1))
				local dist, frames, wonLevel, reason = playGame(stateId, genome)
				if config.debug then print("level: " .. stateId .. " distance: " .. dist .. " frames: " .. frames .. " reason: " .. reason) end
				level.d = dist
				level.f = frames
				level.w = wonLevel
				level.r = reason
			end
		end

		-- Done playing. Determine if we should kill the emulator.
		timeToDie = timeToDie

		-- Send it back yo
		-- TODO just put it all in levels table
		local results_to_send =
			{
				clientId = config.clientId,
				generation = generation,
				species = currentSpecies,
				genome = currentGenome,
				versionCode = VERSION_CODE,
			    levelsPlayed = levels,
			    timeToDie = tostring(timeToDie)
			}

		results_to_send = binser.serialize(results_to_send)

		local now = socket.gettime()
		print("time playing :" .. now - start)
		start = now
		client:send(results_to_send, zmq.NOBLOCK)

		-- Only try to receive results if we're not going to kill ourselves
		if not timeToDie then
			-- The server might send the next level right away
			maybeResponse, err3 = client:recv()
			checkForServerOrderedDeath(maybeResponse)

			if not err3 and maybeResponse ~= "no_level" then
				if config.debug then print("received next level from two-way connection") end
				nextResponseToUse = maybeResponse
			end
		end
		print("time: " .. socket.gettime() - start)
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
		print("Average FPS: " .. frameCount / (socket.gettime() - startTime))
		client:close()
		ctx:term()
		return
	end
end
