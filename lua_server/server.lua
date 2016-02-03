local socket = require("socket")
local server = assert(socket.bind("*", 56506))
-- find out which port the OS chose for us
local ip, port = server:getsockname()
print(ip .. ":" .. port)

-- The number of genomes we've run through (times all levels have been played)
iteration = 0

levels = {
	{fitness = nil, active = true},  -- 1-1
	{fitness = nil, active = true},  -- 1-2
	{fitness = nil, active = true},  -- 1-3
	{fitness = nil, active = false}, -- 1-4
	{fitness = nil, active = true},  -- 2-1
	{fitness = nil, active = true},  -- 2-2
	{fitness = nil, active = true},  -- 2-3
	{fitness = nil, active = false}, -- 2-4
	{fitness = nil, active = false}, -- 3-1
	{fitness = nil, active = true},  -- 3-2
	{fitness = nil, active = true},  -- 3-3
	{fitness = nil, active = false}, -- 3-4
	{fitness = nil, active = true},  -- 4-1
	{fitness = nil, active = true},  -- 4-2
	{fitness = nil, active = true},  -- 4-3
	{fitness = nil, active = false}, -- 4-4
	{fitness = nil, active = false}, -- 5-1
	{fitness = nil, active = true},  -- 5-2
	{fitness = nil, active = true},  -- 5-3
	{fitness = nil, active = false}, -- 5-4
	{fitness = nil, active = false}, -- 6-1
	{fitness = nil, active = false}, -- 6-2
	{fitness = nil, active = false}, -- 6-3
	{fitness = nil, active = false}, -- 6-4
	{fitness = nil, active = false}, -- 7-1
	{fitness = nil, active = false}, -- 7-2
	{fitness = nil, active = false}, -- 7-3
	{fitness = nil, active = false}, -- 7-4
	{fitness = nil, active = false}, -- 8-1
	{fitness = nil, active = false}, -- 8-2
	{fitness = nil, active = false}, -- 8-3
	{fitness = nil, active = false}  -- 8-4
}


levelIndex = 1

function nextUnfinishedLevel()
	local i = levelIndex
	--print("levelIndex: " .. levelIndex)

	for _ = 1, #levels do
		--print(i)

		if levels[i].active and levels[i].fitness == nil then
			levelIndex = (i % #levels) + 1
			return i--levels[i].state
		end

		i = (i % #levels) + 1
	end

	return nil
end

function clearLevels()
	for i = 1, #levels, 1 do
		levels[i].fitness = nil
	end
	levelIndex = 1
	iteration = iteration + 1
end

-- Returns the sum of the fitness for this iteration
function sumFitness()
	local result = 0
	for i = 1, #levels do
		if levels[i].active then
			result = result + levels[i].fitness
		end
	end
	return result
end

function mysplit(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t={} ; i=1
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		t[i] = str
		i = i + 1
	end
	return t
end

-- loop forever waiting for clients
while true do

	-- wait for a connection from any client
	local client = server:accept()
	-- make sure we don't block waiting for this client's line
	client:settimeout(1000000)
	-- receive the line
	local line, err = client:receive()

	-- Was it good?
	if not err then

		local nextLevel = nextUnfinishedLevel()

		-- Is this generation complete?
		if nextLevel == nil then
			-- Process results
			local fitness = sumFitness()
			print("#################### GENERATION " .. iteration .. " FITNESS: " .. fitness .. " #####################")

			-- AI stuff!! TODO

			-- Clear generation. Resets fitness + levelIndex + increments iterationId
			clearLevels()

			-- Get new level
			nextLevel = nextUnfinishedLevel()
		end

		--print("Splitting " .. line)
		toks = mysplit(line, "!")
		for k,v in pairs(toks) do
			--print(k .. ": " .. v)
		end

		if toks[1] == "request" then
			print("game requested. responding with " .. nextLevel)
			client:send(nextLevel .. "!" .. iteration .. "!" .. "TODOAIGOESHERE\n")
		end

		if toks[1] == "results" then
			stateIndex = tonumber(toks[2])
			iterationId = tonumber(toks[3])
			fitnessResult = tonumber(toks[4])

			print("game results received for stateIndex " .. stateIndex .. " iteration " .. iterationId .. " fitness " .. fitnessResult)

			-- Only use fresh results
			if iterationId == iteration then
				levels[stateIndex].fitness = fitnessResult
			end
		end

		--if there was no error, send it back to the client
		--if not err then client:send(line) end
	else
		print("Error: " .. err)
	end

	-- done with client, close the object
	client:close()
end

--[[
print(nextUnfinishedLevel()) -- 1-1
print(nextUnfinishedLevel()) -- 1-2
print(nextUnfinishedLevel()) -- 1-3
print(nextUnfinishedLevel()) -- 2-1
levels[1].fitness = 200
levels[2].fitness = 500
print(nextUnfinishedLevel()) -- should be 1-3
print(nextUnfinishedLevel()) -- should be 2-1
print(nextUnfinishedLevel()) -- should be 1-3
levels[4].fitness = 300
print(nextUnfinishedLevel()) -- should be 1-3
print(nextUnfinishedLevel()) -- should be 1-3
--]]--
