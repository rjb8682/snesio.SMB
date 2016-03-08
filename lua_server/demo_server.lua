local serpent = require("serpent")
local socket = require("socket")
local server = assert(socket.bind("*", 67617))
local ip, port = server:getsockname()
local genomeDir = "backups_dev_3/genomes/"

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

function loadFile(filename)
	local file = io.open(genomeDir .. filename, "r")
	genome = file:read("*line")
	file:close()
	return genome .. "\n"
end

function getBestGenome(file_table)
	local bestFile = nil
	local bestFitness = -1.0
	local regex = "%d+.%d*"
	for key, value in pairs(file_table) do
		toks = mysplit(value)
		for i, filename in pairs(toks) do
			if i > 1 and filename then
				local fitness = string.match(filename, regex)
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
	print("best: " .. bestFile)
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

printf = function(s,...)
	return io.write(s:format(...))
end

while true do
	local client = server:accept()

	-- Receive the line
	local line, err = client:receive()

	-- Was it good?
	if not err and line then
		print("client connected. sending ")

		local file_table = scandir(genomeDir)
		local genome = loadFile(getBestGenome(file_table))

		-- Send them the best we got!
		if genome then
			client:send(genome)
		else
			client:send("nothing\n")
		end
	end

	-- done with client, close the object
	if client then
		client:close()
	end
end
