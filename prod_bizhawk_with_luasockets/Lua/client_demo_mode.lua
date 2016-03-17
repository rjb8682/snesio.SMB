local serpent = require("serpent")
local socket = require("socket")

config = {server="129.21.141.143", port=67617, drawGui=true, drawGenome=true, debug=false, clientId="demo"}
print("Using " .. config.server .. ":" .. config.port)

local runName = "backups_dev" -- default

local shouldSkip = false

client.speedmode(100)

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

function dprint(s)
	if forms.ischecked(debug) then
		console.writeline(s)
	end
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
		if shouldSkip then
			shouldSkip = false
			return 0, 0, 0, "skip", 0
		end
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

		if forms.ischecked(showBanner) then
			gui.drawBox(0, 7, 300, 36, 0xD0FFFFFF, 0xD0FFFFFF)
			local world, level = getWorldAndLevel(stateIndex)
			local multi = 1.0 + (WorldAugmenter*world) + (LevelAugmenter*level)
			gui.drawText(0, 8, "Level: " .. world .. "-" .. level .. " (" .. stateIndex .. ")", 0xFF000000, 11)
			gui.drawText(120, 8, " fitness: " .. math.floor(multi * fitness + maxFitness), 0xFF000000, 11)
			gui.drawText(83, 20, "total fitness: " .. math.floor(genome.fitness), 0xFF000000, 11)
		end

		-- Check for death
		if playerState == 6 or playerState == 0x0B or verticalScreenPosition > 1 then
			local reason = "enemyDeath"
			if verticalScreenPosition > 1 then reason = "fell" end
			dprint(reason)
			return rightmost, currentFrame, 0, reason, stateIndex
		end

		-- Did we win? (set in getPositions)
		if wonLevel then
			wonLevel = false
			dprint("victory")
			return rightmost, currentFrame, 1, "victory", stateIndex
		end

		-- Check for freeze timeout
		freezeTimeout = freezeTimeout - 1
		if freezeTimeout <= 0 or fitness < -100 then
			dprint("freeze")
			return rightmost, currentFrame, 0, "freeze", stateIndex
		end

		-- Check for progress timeout
		progressTimeout = progressTimeout - 1
		if progressTimeout <= 0 or fitness < -100 then
			dprint("noProgress")
			return rightmost, currentFrame, 0, "noProgress", stateIndex
		end
		
		-- Advance frame since we didn't win / die
		currentFrame = currentFrame + 1
		collectgarbage()
		emu.frameadvance()

		if forms.ischecked(showNetwork) then
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

	local dyCell = {}
	dyCell.x = 80
	dyCell.y = 120
	dyCell.value = network.neurons[Inputs-1].value
	cells[Inputs-1] = dyCell

	local biasCell = {}
	biasCell.x = 80
	biasCell.y = 130
	biasCell.value = network.neurons[Inputs].value
	cells[Inputs] = biasCell
	local badCount = 0
	local notBadCount = 0

	for n,neuron in pairs(network.neurons) do
		cell = {}
		if n > Inputs and n <= MaxNodes then
			cell.x = 140
			cell.y = 100
			cell.value = neuron.value
			cells[n] = cell
		end
	end

	for n=1,4 do
		for _,gene in pairs(genome.genes) do
			if gene.enabled then
				local c1 = cells[gene.into]
				local c2 = cells[gene.out]
				if c1 and c2 then
					notBadCount = notBadCount + 1
					if gene.into > Inputs and gene.into <= MaxNodes then
						c1.x = 0.75*c1.x + 0.25*c2.x + 60
						if c1.x >= c2.x then
							c1.x = c1.x - 70
						end

						if c1.x < 90 then
							c1.x = 90
						end
						if c1.x > 210 then
							c1.x = 210
						end
						c1.y = 0.75*c1.y + 0.25*c2.y - 2
						
					end
					if gene.out > Inputs and gene.out <= MaxNodes then
						c2.x = 0.25*c1.x + 0.75*c2.x + 20
						if c1.x >= c2.x then
							c2.x = c2.x + 100
						end

						if c2.x < 90 then
							c2.x = 90
						end
						if c2.x > 210 then
							c2.x = 210
						end
						c2.y = 0.25*c1.y + 0.75*c2.y - 2
					end
				else
					badCount = badCount + 1
				end
			end
		end
	end

	--print("bad count: " .. badCount)
	--print("nbad count: " .. notBadCount)

	for o = 1,Outputs do
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
		gui.drawText(223, 40+8*o, ButtonNames[o], color, 9)
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

	for _,gene in pairs(genome.genes) do
		if gene.enabled then
			local c1 = cells[gene.into]
			local c2 = cells[gene.out]
			local opacity = 0xA0000000
			if c1 and c2 then
				if c1.value == 0 then
					opacity = 0x20000000
				end
				
				local color = 0x80-math.floor(math.abs(sigmoid(gene.weight))*0x80)
				if gene.weight > 0 then 
					color = opacity + 0x8000 + 0x10000*color
				else
					color = opacity + 0x800000 + 0x100*color
				end
				gui.drawLine(c1.x+1, c1.y, c2.x-3, c2.y, color)
			end
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

-- Consider sending an ID of the one we have (or keep track of clientIDs on server)
function getNewGenome()
	-- Connect to server
	local client, err = socket.connect(config.server, config.port)
	if not err then
		bytes, err = client:send(config.clientId .. "!" .. runName .. "\n")
		response, err2 = client:receive()
	end

	-- Close the client
	if client then
		client:close()
	end

	if response and response ~= "nothing" then
		return response
	else
		print("response: " .. tostring(response))
	end
	return nil
end

function skipLevel()
	shouldSkip = true
end

function loadRun()
	runName = forms.gettext(runsDropDown)
	skipLevel()
end

function getRunsList()
	local client, err = socket.connect(config.server, config.port)
	if not err then
		bytes, err = client:send("list\n")
		response, err2 = client:receive()
	end

	-- Close the client
	if client then
		client:close()
	end

	ok, runs = serpent.load(response)
	return runs
end

local width = 500
local height = 500
local lineHeight = 30
form = forms.newform(width, height, "Demo")
showBanner = forms.checkbox(form, "Banner", 10, 10)
showNetwork = forms.checkbox(form, "Network", 10, 50)
skipButton = forms.button(form, "Skip level", skipLevel, 10, 100, 100, 40)

runsDropDown = forms.dropdown(form, getRunsList(), 10, 150, 350, 40)

-- y, x, width, height
loadRunButton = forms.button(form, "Go!", loadRun, 370, 150, 100, 40)
debug = forms.checkbox(form, "Debug", 300, 50)
alwaysShowLatest = forms.checkbox(form, "Always show latest", 10, 350)

forms.setproperty(showBanner, "Checked", true)
forms.setproperty(showNetwork, "Checked", true)
forms.setproperty(alwaysShowLatest, "Checked", true)

-- TODO: dropdown for all possible runs

-- Hook into event loop so that the form gets destroyed
function onExit()
	forms.destroy(form)
end

event.onexit(onExit)

local response = nil
-- loop forever waiting for games to play
while true do
	emu.frameadvance()

	-- Get the first genome
	repeat
		response = getNewGenome()
	until response

	printResult = true

	maxFitness = 0
	for z = 1, 32 do
		-- Avoid castles and water levels
		if z % 4 ~= 0 and z ~= 6 and z ~= 26 then
			ok, genome = serpent.load(response)
			maxFitness = maxFitness + calculateDemoFitness(playGame(z, genome))
		end

		-- Check for a new genome
		local newGenome = getNewGenome()
		if newGenome and response ~= newGenome then
			print("Got a new network")
			if forms.ischecked(alwaysShowLatest) then
				response = newGenome
				printResult = false
				break
			end
		end

	end
	if printResult then
		print("Total max fitness: " .. maxFitness)
	end
end
