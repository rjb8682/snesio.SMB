local serpent = require("serpent")
local zmq = require("zmq")
local bitser = require("bitser")
local socket = require("socket")
bitser.reserveBuffer(1024 * 1024 * 3)

-- Controls when to stop training
local timeToDie = false 
local ButtonNames = {
	"a",
	"left",
	"right"
}

local Inputs = 173
local Outputs = #ButtonNames

-- Increment this when breaking changes are made (will cause old clients to be ignored)
local VERSION_CODE = "ZMQ"

-- Mario's max/min velocities in x and y
local MAX_X_VEL =  40
local MIN_X_VEL = -40
local MAX_Y_VEL =   4
local MIN_Y_VEL =  -5

MaxNodes = 1000000

-- Normalize to [-1, 1]
function normalize(z, min, max)
	return (2 * (z - min) / (max - min)) - 1
end

function evaluateNetwork(network, inputs)
	inputs[#inputs - 2] = normalize(inputs[#inputs - 2], MIN_X_VEL, MAX_X_VEL)
	inputs[#inputs - 1] = normalize(inputs[#inputs - 1], MIN_Y_VEL, MAX_Y_VEL)
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

function loadNetwork(filename)
	local file = io.open(filename, "r")
	local ok, network = serpent.load(file:read("*line"))
	file:close()
	return network
end

-- Global so that we can re-use the network string when possible
networkStr = nil

local server = assert(socket.bind("*", 66616))
local ip, port = server:getsockname()
print("ip: " .. ip .. " port: " .. port)

local response = nil

function playGame(networkStr, client)
	local network = bitser.loads(networkStr)
	assert(network)
	while true do
		local cmd, err = client:receive()
		if cmd == "refresh" then
			-- TODO not really necessary (just do individual levels)
			network = bitser.loads(bits.network)
		elseif cmd == "die" then
			print("All done!")
			client:close()
			return
		elseif tonumber(cmd) then
			local inputs, err = client:receive(tonumber(cmd))
			local outputs = evaluateNetwork(network, bitser.loads(inputs))
			client:send(serpent.dump(outputs) .. "\n")
		else
			print("Wat")
		end
	end
end

-- loop forever waiting for games to play
while true do
	local client = server:accept()
	local bitsComing, err = client:receive()
	print("Received " .. bitsComing)
	bitsComing = tonumber(bitsComing)
	local line, err = client:receive(bitsComing)
	print("Net: " .. line)
	if line then
		playGame(line, client)
	else
		print("Error: " .. err)
	end
end















