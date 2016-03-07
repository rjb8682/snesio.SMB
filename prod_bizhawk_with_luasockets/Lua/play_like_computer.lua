local serpent = require("serpent")

-- TODO: Init to 100%, display on

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
config.drawGui = true
config.blind = true
config.showFitness = false

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

function displayGenome(inputs)
	local cx = 128
	local cy = 120
	local box_rad = 8
	local m = 18

	local cells = {}
	local i = 1
	local cell = {}
	for dy=-BoxRadiusY,BoxRadiusY do
		for dx=-BoxRadiusX,BoxRadiusX do
			cell = {}
			cell.x = cx+m*dx
			cell.y = cy+m*dy
			cell.value = inputs[i]
			cells[i] = cell
			i = i + 1
		end
	end
	
	-- 	gui.drawBox(120-BoxRadiusX*5-3,128-BoxRadiusY*5-3,120+BoxRadiusX*5+2,128+BoxRadiusY*5+2,0xFF000000, 0x80808080)
	local background = 0x80808080
	if config.blind then
		background = 0xFAFAFAFA
	end
	gui.drawBox(cx-(BoxRadiusX*m+22),cy-(BoxRadiusY*m+5),
				cx+(BoxRadiusX*m+22),cy+(BoxRadiusY*m+5),0xFF000000, background)
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
			gui.drawBox(cell.x-box_rad,cell.y-box_rad,cell.x+box_rad,cell.y+box_rad,opacity,color)
		end
	end
	
	XChange = m * ShiftX
	YChange = m * (ShiftY-1)
	gui.drawBox(cx-XChange-box_rad,cy-YChange-box_rad,
				cx-XChange+box_rad,cy-YChange+box_rad,0x00000000,0x80FF0000)
end

function playGame(stateIndex)
	savestate.load(stateIndex .. ".State")

	-- Reset state
	local currentFrame = 0
	local rightmost = 0

	-- Play until we die / win
	while true do
		local inputs = getInputs()
		displayGenome(inputs)

		-- Check how far we are in the level
		if marioX > rightmost then
			rightmost = marioX
		end

		local fitness = rightmost - (currentFrame / 10)

		if config.showFitness then --TODOconfig.drawGui == true then
			gui.drawBox(0, 7, 300, 30, 0xD0FFFFFF, 0xD0FFFFFF)
			local world, level = getWorldAndLevel(stateIndex)
			local multi = 1.0 + (WorldAugmenter*world) + (LevelAugmenter*level)
			gui.drawText(0, 10, " Fitness: " .. math.floor(multi * fitness + maxFitness), 0xFF000000, 11)
			gui.drawText(150, 10, "Level: " .. world .. "-" .. level .. " (" .. stateIndex .. ")", 0xFF000000, 11)
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

		-- Advance frame since we didn't win / die
		currentFrame = currentFrame + 1
		emu.frameadvance()
	end
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
if true then
	percentage = "666" -- I hate globals...
	currentGenome = config.demoFile
	currentSpecies = config.demoFile
	generation = config.demoFile
	maxFitness = 0
	z = 1
	while true do
		-- Avoid castles and water levels
		if z % 4 ~= 0 and z ~= 6 and z ~= 26 then
			maxFitness = maxFitness + calculateDemoFitness(playGame(z))
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
