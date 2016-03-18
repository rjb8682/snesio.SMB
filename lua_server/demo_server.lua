local serpent = require("serpent")
local socket = require("socket")
local server = assert(socket.bind("*", 67617))
local ip, port = server:getsockname()
local runName = "300_run" -- Default run to track
local genomeDir = "/genomes/"

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

function loadFile(filename, dir)
	if not filename then return nil end
	local file = io.open(dir .. filename, "r")
	if file then
		genome = file:read("*line")
		file:close()
		if genome then
			return genome .. "\n"
		end
	end
	return nil
end

function getBestGenome(file_table)
	local bestFile = nil
	local bestFitness = -1.0
	local pat = "%d*%.?%d+"
	for key, value in pairs(file_table) do
		toks = mysplit(value)
		for i, filename in pairs(toks) do
			if filename then
				toks = mysplit(filename, ".genome")
				local fitness = string.match(filename, pat)
				if fitness ~= nil then
					fitness = tonumber(fitness)
					if fitness > bestFitness then
						bestFitness = fitness
						bestFile = filename	
					end
				end
			end
		end
	end
	print("best: " .. tostring(bestFile))
	return bestFile
end

-- Lua implementation of PHP scandir function
function scandir(directory)
    local i, t, popen = 0, {}, io.popen
    for filename in popen('dir "'..directory..'" /b'):lines() do
        i = i + 1
        t[i] = filename
    end
    return t
end

function os.capture(cmd, raw)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    if raw then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r+', ' ')
    return s
end

function getDirs()
    return serpent.dump(mysplit(os.capture("ls -d */", true)))
end

-- Returns all backup dirs
function getDirsOld()
    local dirs = scandir(".")
    local currentDirIndex = nil
    local i = 1
    for l, line in pairs(dirs) do
        toks = mysplit(line)
        for key, value in pairs(toks) do
            print(value)
            if value == ".:" then
                currentDirIndex = i
            end
            dirs[key] = value
            i = i + 1
        end
    end

    -- Remove current dir
    if currentDirIndex then
	    table.remove(dirs, currentDirIndex)
	end

    print(serpent.dump(dirs))
    return serpent.dump(dirs)
end

printf = function(s,...)
	return io.write(s:format(...))
end

while true do
	local client = server:accept()

	-- Receive the line
	local line, err = client:receive()

	-- Was it good?
	if not err and line then
		local toks = mysplit(line, "!")
		local clientId = nil
		local run = runName

        -- Send a list of all runs
        if toks[1] == "list" then
            client:send(getDirs() .. "\n")

        -- Send best genome from specified run
        else
            -- Use custom dir if specified
            if #toks > 1 then
                clientId = toks[1]
                run = toks[2]
            end

            local finalDir = run .. genomeDir
            print("client connected: " .. tostring(clientId))
            print("using run: " .. run)

            local file_table = scandir(finalDir)
            local genome = loadFile(getBestGenome(file_table), finalDir)

            -- Send them the best we got!
            if genome then
                client:send(genome)
            else
                client:send("nothing\n")
            end
        end
	end

	-- done with client, close the object
	if client then
		client:close()
	end
end
