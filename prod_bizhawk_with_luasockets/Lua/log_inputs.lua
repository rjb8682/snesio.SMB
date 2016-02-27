BoxRadius = 6
InputSize = (BoxRadius*2+1)*(BoxRadius*2+1) -- marioVX, marioVY

Inputs = InputSize + 3


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
		s = ""
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
			latex = true

			if latex then
				if inputs[#inputs] >= 0 then
					s = s .. "  "
				else
					s = s .. " "
				end
			end
			s = s .. tostring(inputs[#inputs])
			if latex then
				if dx ~= BoxRadius * 16 then
					s = s .. " &"
				end
			end
		end
		print(s .. " \\\\")
	end
	print("################################################")

	inputs[#inputs+1] = marioVX
	inputs[#inputs+1] = marioVY
	
	return inputs
end

while true do
	getInputs()
	emu.frameadvance();
end