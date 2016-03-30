local serpent = require("serpent")
local socket = require("socket")
local port = 56666
local server = assert(socket.bind("*", port))
local ip, port = server:getsockname()

-- Default experiment to server if none else available
local DEFAULT = "default.experiment"

-- TODO: System to determine current active experiment
-- maybe servers check in with facilitator? idk

-- TODO: Clients won't kill themselves until they connect... fix this. If the server isn't responding,
-- they should kill themselves after a few attempts, that way they get repurposed

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

function getExperimentsList()
    return mysplit(os.capture("ls -d experiments/*", true))
end

function getClientCode(filename)
	file = io.open("codebase/" .. filename, "r")
	code = file:read("*all")
	file:close()
	return code
end

function getExperimentAt(path)
	file = io.open(path, "r")
    if file then
        experiment = file:read("*all")
        file:close()

        -- Compact-ify (experiment format is pretty-printed)
        ok, tab = serpent.load(experiment)
        if ok then
            return tab
        end
    end
	return nil
end

function file_exists(name)
    if name == nil then return false end
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

function getCurrentExperiment()
    -- TODO: support multiple servers?
    local currentConfig = "current_experiments/current.config"
    if file_exists(currentConfig) then
        return getExperimentAt(currentConfig)
    else
        return getExperimentAt(DEFAULT)
    end
end

function getExperiment(experiment_name)
	return getExperimentAt("experiments/" .. experiment_name)
end

function getNewExperimentPath()
    local experiments = getExperimentsList()
    for key, value in pairs(experiments) do
        return value
    end

    return nil
end

function markExperimentComplete(experiment_name)
    -- TODO: support multiple experiments
    local experiment = getCurrentExperiment()
    if experiment then
        io.popen("mv current_experiments/current.config completed_experiments/"
            .. experiment.Name .. "__" .. os.date("%d_%m_%y_%H_%M_%S", os.time()))
    else
        print("No current experiment to mark complete")
    end

end

function markExperimentInProgress(experiment_path)
    io.popen("mv " .. experiment_path .. "  current_experiments/current.config")
end

while true do
	-- Receive the line
	local client = server:accept()
	local line, err = client:receive()
	if line then
		toks = mysplit(line, "!")
		print("received: " .. line .. " -> " .. serpent.line(toks, {comment=false}))
		if toks[1] == "client" then
			print("hello, client!")
			local experiment = getCurrentExperiment()
			local code_file = experiment.ClientCode
			client:send(getClientCode(code_file))
		elseif toks[1] == "server" then
			print("hello, server!")
			if toks[2] then
				print("Experiment complete: " .. toks[2])
                -- io.popen("t dm @tacticalfruit '" .. toks[2] .. "'", "r")
                io.popen("slack-post facilitator 'Experiment `" .. toks[2] .. "` complete'", "r")
                markExperimentComplete(toks[2])
			else
                local newExperimentPath = getNewExperimentPath()
                local experiment = nil
                if file_exists(newExperimentPath) then
    				experiment = getExperimentAt(newExperimentPath)
                else
                    experiment = getExperimentAt(DEFAULT)
                end
                if experiment then
                    if newExperimentPath then
                        print("New experiment path: " .. newExperimentPath)
                        markExperimentInProgress(newExperimentPath)
                    end
                    
                    local result = serpent.dump(experiment)
                    print("Sending config:")
                    print(result)
                    client:send(result)
                else
                    print("No current experiment!")
                    client:send("nothing")
                end
			end
		end

		-- done with client, close the object
		client:close()
	end
end
