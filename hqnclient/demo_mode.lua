local serpent = assert(require("serpent"))
local binser = assert(require("binser"))
local bitser = assert(require("bitser"))
local curses = assert(require("curses"))
local socket = assert(require("socket"))

require("hqnes")
emu.loadrom("smb.nes")
gui.enable()
local SCALE = 5
local FRAMERATE = 61
--gui.setfullscreen(true)
emu.setframerate(FRAMERATE)
gui.setscale(SCALE)

--config = {run="optimize_params_v3_5000_gens", server="snes.bluefile.org", port=67617, drawGui=true, drawGenome=true, debug=false, clientId="demo"}
config = {run="current", server="snes.bluefile.org", port=67617, drawGui=true, drawGenome=true, debug=false, clientId="demo"}
print("Using " .. config.server .. ":" .. config.port)

local frame = 0
local start = socket.gettime()

local memory = memory or mainmemory
local joypad = joypad
local emu = emu
local savestate = savestate

local controller = {}
local inputs = {}


local INC = 15.5

----------------- INPUTS ----------------------------
local ButtonNames = {
	"a",
	"left",
	"right",
}

local BoxRadiusX = 6 -- 6, 6, 2, 0
local BoxRadiusY = 6
local ShiftX = 2
local ShiftY = 2
local InputSize = (BoxRadiusX*2+1)*(BoxRadiusY*2+1)
local Inputs = InputSize + 3 -- marioVX, marioVY, BIAS NEURON
local Outputs = #ButtonNames

-- How many pixels away (manhattan distance) to check for an enemy
local EnemyTolerance = 8

-- Tile types
local BOTTOM_TILE = 84
local BRICK = 82
local COIN = 194
local FLAGPOLE = 37

local ENEMY_TYPES = 0x0016

-- Enemy types
local LIFT_START = 0x24
local LIFT_END = 0x2C
local TRAMPOLINE = 0x32
local PIRANHA = 0x0D

local COIN_SPRITE = 666

-- (shouldn't be conflicting with real enemy types)
local HAMMER_TYPE = 0x0abc0af

-- Hammers
local HAMMER_STATUS_START = 0x002A
local HAMMER_STATUS_END = 0x0032
local HAMMER_HITBOXES = 0x04D0

-- Mario's max/min velocities in x and y
local MAX_X_VEL =  40
local MIN_X_VEL = -40
local MAX_Y_VEL =   4
local MIN_Y_VEL =  -5

----------------- END INPUTS ----------------------------

local ProgressTimeoutConstant = 420	-- 7 seconds
local FreezeTimeoutConstant   = 60	-- 1 second

local MaxNodes = 1000000

local wonLevel = false

-------------------- CURSES ---------------------------
curses.initscr()
curses.cbreak()
curses.echo(false)
curses.nl(true)

local WIDTH  = BoxRadiusX * 2 + 5
local HEIGHT = BoxRadiusY * 2 + 5
local OFFSET = 5

local stdscr  = curses.stdscr()
stdscr:nodelay(true)
local gamescr = curses.newwin(HEIGHT, WIDTH, OFFSET, OFFSET)
local statscr = curses.newwin(10, 30, HEIGHT + OFFSET, OFFSET)

gamescr:border('|', '|', '-', '-', '+', '+', '+', '+')
statscr:border('|', '|', '-', '-', '+', '+', '+', '+')

curses.start_color()
curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK);
curses.init_pair(2, curses.COLOR_RED, curses.COLOR_BLACK);
curses.init_pair(3, curses.COLOR_MAGENTA, curses.COLOR_BLACK);

----------------- END CURSES ---------------------------



-- Normalize to [-1, 1]
function normalize(z, min, max)
	return (2 * (z - min) / (max - min)) - 1
end

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
	-- TODO locals
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
	
	local tile = memory.readbyte(addr)
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
			local hammerAddr = HAMMER_HITBOXES + 4 * (addr - HAMMER_STATUS_START)
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
	local inputIndex = 1
	
	for dy=YStart,YEnd,TWIDTH do
		for dx=XStart,XEnd,TWIDTH do
			inputs[inputIndex] = 0
			
			--print("dx: " .. dx .. " dy: " .. dy)
			for i = 1,#sprites do
				-- Lifts are sprites, but not enemies. Make them a 1.
				-- TODO: Trampolines??
				local sprite = sprites[i]
				local distx = 999
				local disty = 999
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
						inputs[inputIndex] = 1
					elseif sprite.t == COIN_SPRITE then
						inputs[inputIndex] = 0
					else
						inputs[inputIndex] = -1
					end
				end
			end

			-- Write tiles AFTER sprites, so that vines don't show up
			-- on top of pipes even when they're inside.
			-- This means that hammer bros jumping are briefly not shown
			local tile = getTile(dx, dy)
			if tile == 1 and marioY+dy < 0x1B0 then
				inputs[inputIndex] = 1
			end

			inputIndex = inputIndex + 1
		end
	end

	inputs[inputIndex + 0] = marioVX
	inputs[inputIndex + 1] = marioVY
	inputs[inputIndex + 2] = 1 -- Bias

	--printBoard(inputs)

	return inputs
end

function dprint(s)
	io.stdout:write(s .. "\n")
end


local lastPrinted = socket.gettime()
function printBoard(inputs)
	local increment = 1 / INC
	local now = socket.gettime()
	if now < (lastPrinted + increment) then
		socket.sleep((lastPrinted + increment) - now)
	end
	local c = 1
	for row=1,13 do
		for col=1,13 do
			if row == 6 and col == 5 then
				gamescr:attron(curses.color_pair(2))
				gamescr:mvaddch(row+1, col+1, "m")
				gamescr:attroff(curses.color_pair(2))
			elseif inputs[c] > 0 then
				gamescr:mvaddch(row+1, col+1, "#")
			elseif inputs[c] < 0 then
				gamescr:attron(curses.color_pair(3))
				gamescr:mvaddch(row+1, col+1, "#")
				gamescr:attroff(curses.color_pair(3))
			else
				gamescr:mvaddch(row+1, col+1, " ")
			end
			c = c + 1
		end
	end
	gamescr:refresh()
	lastPrinted = socket.gettime()
end

function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end
-- TODO: One inputs table that we re-clear
function evaluateNetwork(network, inputs)
	if #inputs ~= Inputs then
		io.stdout:write("Incorrect number of neural network inputs.")
		io.stdout:write(#inputs)
		io.stdout:write(Inputs)
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
	
	for o=1,Outputs do
		local button = ButtonNames[o]
		if network.neurons[MaxNodes+o].value > 0 then
			controller[button] = true
		else
			controller[button] = false
		end
	end
	
	return controller
end

function clearJoypad()
	for b = 1,#ButtonNames do
		controller[ButtonNames[b]] = false
	end
	joypad.set(controller, 0)
end

function evaluateCurrent(network)
	inputs = getInputs()
	controller = evaluateNetwork(network, inputs)
	
	if controller["left"] and controller["right"] then
		controller["left"] = false
		controller["right"] = false
	end

	-- Force running
	controller["b"] = true
end

local saveStateNums = 0
function playGame(stateIndex, genome)
	local network = genome.network 
	savestate.load(stateIndex .. ".State")
	saveStateNums = saveStateNums + 1

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
		--print("Setting to: " .. serpent.line(controller))
		joypad.set(controller, 0)

		-- Check how far we are in the level
		if marioX > rightmost then
			rightmost = marioX
			progressTimeout = ProgressTimeoutConstant
		end

		if oldMarioX ~= marioX or oldMarioY ~= marioY then
			freezeTimeout = FreezeTimeoutConstant
		end

		local fitness = rightmost - (currentFrame / 4)

		local curEstimate = calculateDemoFitness(rightmost, currentFrame, 0, "noProgress", stateIndex)
		statscr:mvaddstr(2, 2, "Total fitness: " .. maxFitness + curEstimate)
		local world, level = getWorldAndLevel(stateIndex)
		statscr:mvaddstr(3, 2, "World: " .. tostring(world) .. "-" .. tostring(level))
		statscr:mvaddstr(4, 2, tostring(frame / (socket.gettime() - start)))
		statscr:refresh()

		-- Check for death
		if playerState == 6 or playerState == 0x0B or verticalScreenPosition > 1 then
			local reason = "enemyDeath"
			if verticalScreenPosition > 1 then reason = "fell" end
			return rightmost, currentFrame, 0, reason, stateIndex
		end

		-- Did we win? (set in getPositions)
		if wonLevel then
			wonLevel = false
			return rightmost, currentFrame, 1, "victory", stateIndex
		end

		-- Check for freeze timeout
		freezeTimeout = freezeTimeout - 1
		if freezeTimeout <= 0 or fitness < -100 then
			return rightmost, currentFrame, 0, "freeze", stateIndex
		end

		-- Check for progress timeout
		progressTimeout = progressTimeout - 1
		if progressTimeout <= 0 or fitness < -100 then
			return rightmost, currentFrame, 0, "noProgress", stateIndex
		end

		if true then
			displayGenome(genome)	
		end
		
		-- Advance frame since we didn't win / die
		currentFrame = currentFrame + 1
		emu.frameadvance()
		frame = frame + 1

		local input = stdscr:getch()
		statscr:mvaddstr(6, 2, tostring(input) .. "        ")
		if input == 45 then
			-- -
			FRAMERATE = FRAMERATE - 10
			emu.setframerate(FRAMERATE)
		elseif input == 61 then
			-- +
			FRAMERATE = FRAMERATE + 10
			emu.setframerate(FRAMERATE)
		end	
	end
end

function loadNetworkFile(filename)
	local file = io.open(filename, "rb")
	local line = file:read("*all")
	file:close()
	return line
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
    text(58, 105, "vx",   0xCCCCCCCC, 8)
	
    local dyCell = {}
    dyCell.x = 80
    dyCell.y = 120
    dyCell.value = network.neurons[Inputs-1].value
    cells[Inputs-1] = dyCell
    text(58, 115, "vy",   0xCCCCCCCC, 8)

    local biasCell = {}
    biasCell.x = 80
    biasCell.y = 130
    biasCell.value = network.neurons[Inputs].value
    cells[Inputs] = biasCell
    text(58, 125, "bias", 0xCCCCCCCC, 8)

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
            color = 0x55FF55FF
        else
            color = 0x3333333F
        end
        text(226, 42 + 8*o, ButtonNames[o], color, 8)
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
local WorldAugmenter = 0.2
local LevelAugmenter = 0.1
function getWorldAndLevel(i)
	local world = math.floor((i - 1) / 4) + 1
	local level = ((i - 1) % 4) + 1
	return world, level
end

function calculateDemoFitness(distance, frames, wonLevel, reason, stateIndex)
	--dprint("distance " .. distance .. " frames " .. frames .. " wonLevel " .. wonLevel .. " reason " .. reason .. " stateIndex " .. stateIndex)
	local result = distance
	local timePenalty = frames / 10
	if wonLevel == 1 then
		result = result + 5000
	end

	local world, level = getWorldAndLevel(stateIndex)
	local multi = 1.0 + (WorldAugmenter*world) + (LevelAugmenter*level)

	return 100 + (multi * result) - timePenalty
end

-- loop forever waiting for games to play
--local networkStr = loadNetworkFile("68745.1_56586975.genome")
--local networkStr = loadNetworkFile("164309.5_3397366110.genome")
--local networkStr = loadNetworkFile("175811_4301594969.genome")
--local networkStr = loadNetworkFile("177170.7_5570641317.genome")
--local networkStr = loadNetworkFile("18895.6_6355209176.genome")
--local networkStr = loadNetworkFile("48506.4_6365684496.genome") -- bad
--local networkStr = loadNetworkFile("38043.5_6361451322.genome")
--local networkStr = loadNetworkFile("189416.4_7032364562.genome")
--local networkStr = loadNetworkFile("17869.3_6368966519.genome")
local networkStr = loadNetworkFile("181404_13508766012.genomebitser")


function getNewGenome()
	-- Connect to server
	local client, err = socket.connect(config.server, config.port)
	if not err then
		bytes, err = client:send(config.clientId .. "!" .. config.run .. "\n")
		responseSize, err2 = client:receive("*line")
		responseSize = tonumber(responseSize)
		if responseSize and responseSize > 0 then
			response, err = client:receive(responseSize)
		end
	end

	-- Close the client
	if client then
		client:close()
	end

	return response
end

maxFitness = 0

DEMO = true

while true do
	-- Get the first genome
	local printResult = true

	if DEMO then
		networkStr = getNewGenome()
	end

	maxFitness = 0
	results = {}
	for z = 1, 32 do
		-- Avoid castles and water levels
		if z % 4 ~= 0 and z ~= 6 and z ~= 26 then
			local genome = binser.deserializeN(networkStr, 1)
			statscr:mvaddstr(5, 2, "Max fitness: " .. genome.fitness)
			statscr:refresh()
			world, level = getWorldAndLevel(z)
			newFitness = calculateDemoFitness(playGame(z, genome))
			results[z] = "world: " .. world .. "-" .. level .. " " .. newFitness
			maxFitness = maxFitness + newFitness
		end
	end
	if printResult then
		dprint("Total max fitness: " .. maxFitness)
		dprint(serpent.dump(results))
	end
end
