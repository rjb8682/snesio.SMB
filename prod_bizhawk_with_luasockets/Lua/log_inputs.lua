BoxRadiusX = 6 -- 6, 6, 2, 0
BoxRadiusY = 6
ShiftX = 2
ShiftY = 2
InputSize = (BoxRadiusX*2+1)*(BoxRadiusY*2+1)

-- How many pixels away (manhattan distance) to check for an enemy
EnemyTolerance = 8

Inputs = InputSize + 3 -- marioVX, marioVY, BIAS NEURON

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
		
		tile = memory.readbyte(addr)
		-- Don't let Mario see coins.
		if tile ~= 0 and tile ~= COIN then
			--print(tostring(x) .. ", " .. tostring(y) .. ": " .. tostring(memory.readbyte(addr)))
			return 1
		else
			return 0
		end
	end
end

function getSprites()
	--print("-----sprites--------")
	if gameinfo.getromname() == "Super Mario Bros." then
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
	local cells = {}
	local i = 1
	local cell = {}
	for dy=-BoxRadiusY,BoxRadiusY do
		for dx=-BoxRadiusX,BoxRadiusX do
			cell = {}
			cell.x = 50+5*dx
			cell.y = 70+5*dy
			cell.value = inputs[i]
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
	
	XChange = ShiftX * 6
	YChange = ShiftY * 5
	gui.drawBox(49-XChange,72-YChange,55-XChange,78-YChange,0x00000000,0x80FF0000)
end

while true do
	inputs = getInputs()
	displayGenome(inputs)
	emu.frameadvance();
end