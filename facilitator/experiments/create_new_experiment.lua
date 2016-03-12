local serpent = assert(require("serpent"))
local socket = assert(require("socket"))
math.randomseed(socket.gettime() * 1000)

local box_radius = 6
local button_names = {
	"A",
	"Left",
	"Right",
}
local input_size = (box_radius * 2 + 1)*(box_radius * 2 + 1)
local inputs = input_size + 3 -- marioVX, marioVY, bias

local default_experiment = {
	VERSION_CODE = math.floor(math.random() * 1000000000), -- Don't even THINK about fucking with this
	Name = "default_experiment",
	ClientCode = "default_client_logic.lua", -- Client code *must* contain VERSION_CODE,
	StopGeneration = -1,
	StopTimeSeconds = -1,
	StopFitness = -1,
	Port = 56506,

	ButtonNames = button_names,
	BoxRadius = box_radius,
	InputSize = input_size,
	Inputs = inputs,
	Outputs = #button_names,

	Population = 300,
	DeltaDisjoint = 2.0,
	DeltaWeights = 0.4,
	DeltaThreshold = 1.0,
	StaleSpecies = 15,

	MutateConnectionsChance = 0.25,
	PerturbChance = 0.90,
	CrossoverChance = 0.75,
	LinkMutationChance = 2.0,
	NodeMutationChance = 0.50,
	BiasMutationChance = 0.40,
	StepSize = 0.1,
	DisableMutationChance = 0.4,
	EnableMutationChance = 0.2,

	WorldAugmenter = 0.2, -- 20% increase in fitness per world (2-4 is 20% more than 1-4)
	LevelAugmenter = 0.1, -- 10% increase in fitness per level (3-2 is 10% more than 3-1)

	MaxNodes = 1000000 -- This just needs to be very high,
}

local serialized, err = serpent.block(default_experiment, {comment=false})
if err then
	print(err)
	return
end

print(serialized)