local serpent = require("serpent")
local socket = require("socket")
local port = 56506
local server = assert(socket.bind("*", port))
local udp = assert(socket.udp("*", port))
local ip, port = server:getsockname()

-- How many generations do we wait to save?
SAVE_EVERY_N_GENERATIONS = 5

-- Where to save backups
backupDir = "backups_dev_4/"

ButtonNames = {
	"A",
	"Left",
	"Right",
}

-- GA parameters -- 
BoxRadius = 6
InputSize = (BoxRadius*2+1)*(BoxRadius*2+1) -- marioVX, marioVY

Inputs = InputSize + 3
Outputs = #ButtonNames

Population = 50
DeltaDisjoint = 2.0
DeltaWeights = 0.4
DeltaThreshold = 1.0

StaleSpecies = 15

MutateConnectionsChance = 0.25
PerturbChance = 0.90
CrossoverChance = 0.75
LinkMutationChance = 2.0
NodeMutationChance = 0.50
BiasMutationChance = 0.40
StepSize = 0.1
DisableMutationChance = 0.4
EnableMutationChance = 0.2

WorldAugmenter = 0.2
LevelAugmenter = 0.1

MaxNodes = 1000000

NUM_DISPLAY_COLS = 50
NUM_DISPLAY_ROWS = Population / NUM_DISPLAY_COLS

---- Set up curses
local curses = require("curses")
curses.initscr()
curses.cbreak()
curses.echo(false)
curses.nl(true)
--local stdscr = curses.stdscr()

-- left column
local lcolwidth = NUM_DISPLAY_COLS + 2
local ypos = 0
local bannerscrheight = 4
local genomescrheight = NUM_DISPLAY_ROWS + 2
local histoscrheight = 24
local statscrheight = 33

local bannerscr = curses.newwin(bannerscrheight, lcolwidth, ypos, 0)
ypos = ypos + bannerscrheight - 1
local genomescr = curses.newwin(genomescrheight, lcolwidth, ypos, 0)
ypos = ypos + genomescrheight - 1
local histoscr  = curses.newwin(histoscrheight,  lcolwidth, ypos, 0)
ypos = ypos + histoscrheight - 1
local statscr   = curses.newwin(statscrheight,   lcolwidth, ypos, 0)
ypos = ypos + statscrheight - 1

-- right column
local rcolx = lcolwidth + 2
-- -10 to omit non-played levels
local levelscr  = curses.newwin(36 - 10, 60, 0, rcolx)
local clientscr = curses.newwin(statscrheight, 60, 35 - 10, rcolx)

--stdscr:clear()
bannerscr:clear()
genomescr:clear()
histoscr:clear()
clientscr:clear()
levelscr:clear()
statscr:clear()

bannerscr:border('|', '|', '-', '-', '+', '+', '+', '+')
genomescr:border('|', '|', '-', '-', '+', '+', '+', '+')
histoscr:border ('|', '|', '-', '-', '+', '+', '+', '+')
clientscr:border('|', '|', '-', '-', '+', '+', '+', '+')
levelscr:border ('|', '|', '-', '-', '+', '+', '+', '+')
statscr:border  ('|', '|', '-', '-', '+', '+', '+', '+')

curses.start_color()
curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK);
curses.init_pair(2, curses.COLOR_RED, curses.COLOR_BLACK);
curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_WHITE);
-----------------

-- The number of genomes we've run through (times all levels have been played)
iteration = 0

-- Increment this when breaking changes are made (will cause old clients to be ignored)
local VERSION_CODE = 8

-- New field: totalFrames. TODO: consider using average frames over the last 100
-- iterations for example. May not be worth the extra work, honestly. Even easier
-- is resetting totalFrames every so often for a similar effect.
levels = {
	{a = true},  -- 1-1
	{a = true},  -- 1-2
	{a = true},  -- 1-3
	{a = false}, -- 1-4, castle
	{a = true},  -- 2-1
	{a = false}, -- 2-2, water level
	{a = true},  -- 2-3
	{a = false}, -- 2-4, castle
	{a = true},  -- 3-1
	{a = true},  -- 3-2
	{a = true},  -- 3-3
	{a = false}, -- 3-4, castle
	{a = true},  -- 4-1
	{a = true},  -- 4-2
	{a = true},  -- 4-3
	{a = false}, -- 4-4, castle
	{a = true},  -- 5-1
	{a = true},  -- 5-2,
	{a = true},  -- 5-3
	{a = false}, -- 5-4, castle
	{a = true},  -- 6-1
	{a = true},  -- 6-2
	{a = true},  -- 6-3
	{a = false}, -- 6-4, castle
	{a = true},  -- 7-1
	{a = false}, -- 7-2, water level
	{a = true},  -- 7-3
	{a = false}, -- 7-4, castle
	{a = true},  -- 8-1
	{a = true},  -- 8-2
	{a = true},  -- 8-3
	{a = false}  -- 8-4, castle
}

jobs = {}

-- This table keeps track of how many results + frames each client has returned
-- This only increments when a client is the *first* to return a level's result
clients = {}

function clearLevels()
	for i = 1, #levels, 1 do
		if not levels[i].f then
			levels[i].f = 0
		end
		if not levels[i].timesWon then
			levels[i].timesWon = 0
		end

		if not levels[i].totalFrames then
			levels[i].totalFrames = 0
		end
		levels[i].fitness = nil
		levels[i].lastRequester = ""
		levels[i].reason = ""
	end
	levelIndex = 1
	iteration = iteration + 1
end

function getWorldAndLevel(i)
	local world = math.floor((i - 1) / 4) + 1
	local level = ((i - 1) % 4) + 1
	return world, level
end

-- Returns the sum of the fitness for this iteration
function sumFitness()
	local result = 0
	for i = 1, #levels do
		if levels[i].a then
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

function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end

function newInnovation()
	pool.innovation = pool.innovation + 1
	return pool.innovation
end

function newPool()
	--print("CALLING NEWPOOL")
	local pool = {}
	pool.species = {}
	pool.generation = 0
	pool.innovation = Outputs
	pool.currentSpecies = 1
	pool.currentGenome = 1
	pool.currentFrame = 0
	pool.maxFitness = 0
	
	return pool
end

function newSpecies()
	local species = {}
	species.topFitness = 0
	species.staleness = 0
	species.genomes = {}
	species.averageFitness = 0
	
	return species
end

function newGenome()
	local genome = {}
	genome.genes = {}
	genome.fitness = 0
	genome.adjustedFitness = 0
	genome.network = {}
	genome.maxneuron = 0
	genome.globalRank = 0
	genome.mutationRates = {}
	genome.mutationRates["connections"] = MutateConnectionsChance
	genome.mutationRates["link"] = LinkMutationChance
	genome.mutationRates["bias"] = BiasMutationChance
	genome.mutationRates["node"] = NodeMutationChance
	genome.mutationRates["enable"] = EnableMutationChance
	genome.mutationRates["disable"] = DisableMutationChance
	genome.mutationRates["step"] = StepSize
	
	return genome
end

function copyGenome(genome)
	local genome2 = newGenome()
	for g=1,#genome.genes do
		table.insert(genome2.genes, copyGene(genome.genes[g]))
	end
	genome2.maxneuron = genome.maxneuron
	genome2.mutationRates["connections"] = genome.mutationRates["connections"]
	genome2.mutationRates["link"] = genome.mutationRates["link"]
	genome2.mutationRates["bias"] = genome.mutationRates["bias"]
	genome2.mutationRates["node"] = genome.mutationRates["node"]
	genome2.mutationRates["enable"] = genome.mutationRates["enable"]
	genome2.mutationRates["disable"] = genome.mutationRates["disable"]
	
	return genome2
end

function basicGenome()
	local genome = newGenome()
	local innovation = 1

	genome.maxneuron = Inputs
	mutate(genome)
	
	return genome
end

function newGene()
	local gene = {}
	gene.into = 0
	gene.out = 0
	gene.weight = 0.0
	gene.enabled = true
	gene.innovation = 0
	
	return gene
end

function copyGene(gene)
	local gene2 = newGene()
	gene2.into = gene.into
	gene2.out = gene.out
	gene2.weight = gene.weight
	gene2.enabled = gene.enabled
	gene2.innovation = gene.innovation
	
	return gene2
end

function newNeuron()
	local neuron = {}
	neuron.incoming = {}
	neuron.value = 0.0
	
	return neuron
end

function generateNetwork(genome)
	local network = {}
	network.neurons = {}
	
	for i=1,Inputs do
		network.neurons[i] = newNeuron()
	end
	
	for o=1,Outputs do
		network.neurons[MaxNodes+o] = newNeuron()
	end
	
	table.sort(genome.genes, function (a,b)
		return (a.out < b.out)
	end)
	for i=1,#genome.genes do
		local gene = genome.genes[i]
		if gene.enabled then
			if network.neurons[gene.out] == nil then
				network.neurons[gene.out] = newNeuron()
			end
			local neuron = network.neurons[gene.out]
			table.insert(neuron.incoming, gene)
			if network.neurons[gene.into] == nil then
				network.neurons[gene.into] = newNeuron()
			end
		end
	end
	
	genome.network = network
end

function crossover(g1, g2)
	-- Make sure g1 is the higher fitness genome
	if g2.fitness > g1.fitness then
		tempg = g1
		g1 = g2
		g2 = tempg
	end

	local child = newGenome()
	
	local innovations2 = {}
	for i=1,#g2.genes do
		local gene = g2.genes[i]
		innovations2[gene.innovation] = gene
	end
	
	for i=1,#g1.genes do
		local gene1 = g1.genes[i]
		local gene2 = innovations2[gene1.innovation]
		if gene2 ~= nil and math.random(2) == 1 and gene2.enabled then
			table.insert(child.genes, copyGene(gene2))
		else
			table.insert(child.genes, copyGene(gene1))
		end
	end
	
	child.maxneuron = math.max(g1.maxneuron,g2.maxneuron)
	
	for mutation,rate in pairs(g1.mutationRates) do
		child.mutationRates[mutation] = rate
	end
	
	return child
end

function randomNeuron(genes, nonInput)
	local neurons = {}
	if not nonInput then
		for i=1,Inputs do
			neurons[i] = true
		end
	end
	for o=1,Outputs do
		neurons[MaxNodes+o] = true
	end
	for i=1,#genes do
		if (not nonInput) or genes[i].into > Inputs then
			neurons[genes[i].into] = true
		end
		if (not nonInput) or genes[i].out > Inputs then
			neurons[genes[i].out] = true
		end
	end

	local count = 0
	for _,_ in pairs(neurons) do
		count = count + 1
	end
	local n = math.random(1, count)
	
	for k,v in pairs(neurons) do
		n = n-1
		if n == 0 then
			return k
		end
	end
	
	return 0
end

function containsLink(genes, link)
	for i=1,#genes do
		local gene = genes[i]
		if gene.into == link.into and gene.out == link.out then
			return true
		end
	end
end

function pointMutate(genome)
	local step = genome.mutationRates["step"]
	
	for i=1,#genome.genes do
		local gene = genome.genes[i]
		if math.random() < PerturbChance then
			gene.weight = gene.weight + math.random() * step*2 - step
		else
			gene.weight = math.random()*4-2
		end
	end
end

function linkMutate(genome, forceBias)
	local neuron1 = randomNeuron(genome.genes, false)
	local neuron2 = randomNeuron(genome.genes, true)
	 
	local newLink = newGene()
	if neuron1 <= Inputs and neuron2 <= Inputs then
		--Both input nodes
		return
	end
	if neuron2 <= Inputs then
		-- Swap output and input
		local temp = neuron1
		neuron1 = neuron2
		neuron2 = temp
	end

	newLink.into = neuron1
	newLink.out = neuron2
	if forceBias then
		newLink.into = Inputs
	end
	
	if containsLink(genome.genes, newLink) then
		return
	end
	newLink.innovation = newInnovation()
	newLink.weight = math.random()*4-2
	
	table.insert(genome.genes, newLink)
end

function nodeMutate(genome)
	if #genome.genes == 0 then
		return
	end

	genome.maxneuron = genome.maxneuron + 1

	local gene = genome.genes[math.random(1,#genome.genes)]
	if not gene.enabled then
		return
	end
	gene.enabled = false
	
	local gene1 = copyGene(gene)
	gene1.out = genome.maxneuron
	gene1.weight = 1.0
	gene1.innovation = newInnovation()
	gene1.enabled = true
	table.insert(genome.genes, gene1)
	
	local gene2 = copyGene(gene)
	gene2.into = genome.maxneuron
	gene2.innovation = newInnovation()
	gene2.enabled = true
	table.insert(genome.genes, gene2)
end

function enableDisableMutate(genome, enable)
	local candidates = {}
	for _,gene in pairs(genome.genes) do
		if gene.enabled == not enable then
			table.insert(candidates, gene)
		end
	end
	
	if #candidates == 0 then
		return
	end
	
	local gene = candidates[math.random(1,#candidates)]
	gene.enabled = not gene.enabled
end

function mutate(genome)
	for mutation,rate in pairs(genome.mutationRates) do
		if math.random(1,2) == 1 then
			genome.mutationRates[mutation] = 0.95*rate
		else
			genome.mutationRates[mutation] = 1.05263*rate
		end
	end

	if math.random() < genome.mutationRates["connections"] then
		pointMutate(genome)
	end
	
	local p = genome.mutationRates["link"]
	while p > 0 do
		if math.random() < p then
			linkMutate(genome, false)
		end
		p = p - 1
	end

	p = genome.mutationRates["bias"]
	while p > 0 do
		if math.random() < p then
			linkMutate(genome, true)
		end
		p = p - 1
	end
	
	p = genome.mutationRates["node"]
	while p > 0 do
		if math.random() < p then
			nodeMutate(genome)
		end
		p = p - 1
	end
	
	p = genome.mutationRates["enable"]
	while p > 0 do
		if math.random() < p then
			enableDisableMutate(genome, true)
		end
		p = p - 1
	end

	p = genome.mutationRates["disable"]
	while p > 0 do
		if math.random() < p then
			enableDisableMutate(genome, false)
		end
		p = p - 1
	end
end

function disjoint(genes1, genes2)
	local i1 = {}
	for i = 1,#genes1 do
		local gene = genes1[i]
		i1[gene.innovation] = true
	end

	local i2 = {}
	for i = 1,#genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = true
	end
	
	local disjointGenes = 0
	for i = 1,#genes1 do
		local gene = genes1[i]
		if not i2[gene.innovation] then
			disjointGenes = disjointGenes+1
		end
	end
	
	for i = 1,#genes2 do
		local gene = genes2[i]
		if not i1[gene.innovation] then
			disjointGenes = disjointGenes+1
		end
	end
	
	local n = math.max(#genes1, #genes2)
	
	return disjointGenes / n
end

function weights(genes1, genes2)
	local i2 = {}
	for i = 1,#genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = gene
	end

	local sum = 0
	local coincident = 0
	for i = 1,#genes1 do
		local gene = genes1[i]
		if i2[gene.innovation] ~= nil then
			local gene2 = i2[gene.innovation]
			sum = sum + math.abs(gene.weight - gene2.weight)
			coincident = coincident + 1
		end
	end
	
	return sum / coincident
end
	
function sameSpecies(genome1, genome2)
	local dd = DeltaDisjoint*disjoint(genome1.genes, genome2.genes)
	local dw = DeltaWeights*weights(genome1.genes, genome2.genes) 
	return dd + dw < DeltaThreshold
end

function rankGlobally()
	local global = {}
	for s = 1,#pool.species do
		local species = pool.species[s]
		for g = 1,#species.genomes do
			table.insert(global, species.genomes[g])
		end
	end
	table.sort(global, function (a,b)
		return (a.fitness < b.fitness)
	end)
	
	for g=1,#global do
		global[g].globalRank = g
	end
end

function calculateAverageFitness(species)
	local total = 0
	
	for g=1,#species.genomes do
		local genome = species.genomes[g]
		total = total + genome.globalRank
	end
	
	species.averageFitness = total / #species.genomes
end

function totalAverageFitness()
	local total = 0
	for s = 1,#pool.species do
		local species = pool.species[s]
		total = total + species.averageFitness
	end

	return total
end

function cullSpecies(cutToOne)
	for s = 1,#pool.species do
		local species = pool.species[s]
		
		table.sort(species.genomes, function (a,b)
			return (a.fitness > b.fitness)
		end)
		
		local remaining = math.ceil(#species.genomes/2)
		if cutToOne then
			remaining = 1
		end
		while #species.genomes > remaining do
			table.remove(species.genomes)
		end
	end
end

function breedChild(species)
	local child = {}
	if math.random() < CrossoverChance then
		g1 = species.genomes[math.random(1, #species.genomes)]
		g2 = species.genomes[math.random(1, #species.genomes)]
		child = crossover(g1, g2)
	else
		g = species.genomes[math.random(1, #species.genomes)]
		child = copyGenome(g)
	end
	
	mutate(child)
	
	return child
end

function removeStaleSpecies()
	local survived = {}

	for s = 1,#pool.species do
		local species = pool.species[s]
		
		table.sort(species.genomes, function (a,b)
			return (a.fitness > b.fitness)
		end)
		
		if species.genomes[1].fitness > species.topFitness then
			species.topFitness = species.genomes[1].fitness
			species.staleness = 0
		else
			species.staleness = species.staleness + 1
		end
		if species.staleness < StaleSpecies or species.topFitness >= pool.maxFitness then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end

function removeWeakSpecies()
	local survived = {}

	local sum = totalAverageFitness()
	for s = 1,#pool.species do
		local species = pool.species[s]
		breed = math.floor(species.averageFitness / sum * Population)
		if breed >= 1 then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end


function addToSpecies(child)
	local foundSpecies = false
	for s=1,#pool.species do
		local species = pool.species[s]
		if not foundSpecies and sameSpecies(child, species.genomes[1]) then
			table.insert(species.genomes, child)
			foundSpecies = true
		end
	end
	
	if not foundSpecies then
		local childSpecies = newSpecies()
		table.insert(childSpecies.genomes, child)
		table.insert(pool.species, childSpecies)
	end
end

function generateJobQueue()
	local jobs = {}
	for s = 1, #pool.species do
		for g = 1, #pool.species[s].genomes do
			table.insert(jobs, {species=s, genome=g})
		end
	end
	jobs.index = 1
	return jobs
end

function newGeneration()
	sendStaleMsgToAllClients()

	cullSpecies(false) -- Cull the bottom half of each species
	rankGlobally()
	removeStaleSpecies()
	rankGlobally()
	for s = 1,#pool.species do
		local species = pool.species[s]
		calculateAverageFitness(species)
	end
	removeWeakSpecies()
	local sum = totalAverageFitness()
	local children = {}
	for s = 1,#pool.species do
		local species = pool.species[s]
		breed = math.floor(species.averageFitness / sum * Population) - 1
		for i=1,breed do
			table.insert(children, breedChild(species))
		end
	end
	cullSpecies(true) -- Cull all but the top member of each species
	while #children + #pool.species < Population do
		local species = pool.species[math.random(1, #pool.species)]
		table.insert(children, breedChild(species))
	end
	for c=1,#children do
		local child = children[c]
		addToSpecies(child)
	end
	
	pool.generation = pool.generation + 1
	jobs = generateJobQueue()
end
	
function initializePool()
	--print("initializePool")
	pool = newPool()

	for i=1,Population do
		basic = basicGenome()
		addToSpecies(basic)
	end

	initializeRun()
end

function initializeRun()
	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]
	generateNetwork(genome)
end

--print("is pool nil?")
if pool == nil then
	--print("yup")
	initializePool()
end

function currentJobGenome()
	local job = jobs[jobs.index]
	return pool.species[job.species].genomes[job.genome]
end

function allJobsComplete()
	for i = 1, #jobs do
		if pool.species[jobs[i].species].genomes[jobs[i].genome].fitness == 0 then
			return false
		end
	end
	return true
end

-- Advance the index. Assumes there is still a non-finished job available.
function advanceJobsIndex() 
	repeat	
		jobs.index = jobs.index + 1
		if jobs.index > #jobs then
			jobs.index = 1
		end
	until currentJobGenome().fitness == 0
	jobs[jobs.index].requested = true
end

-- TODO: make sure we don't send a genome if we just got that genome's results!!
function findNextNonRequestedGenome()
	if not jobs then
		jobs = generateJobQueue()
	end

	-- If there are no more jobs, then make a new generation.
	if allJobsComplete() then
		newGeneration()
	end

	local index = jobs.index

	pool.currentSpecies = jobs[index].species
	pool.currentGenome = jobs[index].genome
	advanceJobsIndex()
end

function nextGenome()
	pool.currentGenome = pool.currentGenome + 1
	if pool.currentGenome > #pool.species[pool.currentSpecies].genomes then
		pool.currentGenome = 1
		pool.currentSpecies = pool.currentSpecies+1
		if pool.currentSpecies > #pool.species then
			newGeneration()
			pool.currentSpecies = 1
		end
	end
end

function fitnessAlreadyMeasured()
	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]
	
	return genome.fitness ~= 0
end

function writeFile(filename)
	-- TODO: turn on when ready
	local file = io.open(backupDir .. filename, "w")
	file:write(serpent.dump(pool))
	file:write("\n")
	file:write(serpent.dump(levels))
	file:write("\n")
	file:write(serpent.dump(clients))
	file:write("\n")
	file:write(serpent.dump(jobs))
    file:close()
end

function writeNetwork(filename, network)
	-- TODO: turn off when ready
	--local file = io.open(backupDir .. "networks/" .. filename, "w")
	--file:write(serpent.dump(network))
	--file:write("\n")
	--file:close()
end

-- TODO: This supercedes writeNetwork. Test to make sure they're equivalent, and if not,
-- just save both in the same file.
function writeGenome(filename, genome)
	-- TODO: turn on when ready
	local file = io.open(backupDir .. "genomes/" .. filename, "w")
	file:write(serpent.dump(genome))
	file:write("\n")
	file:close()
end

function loadFile(filename)
	local file = io.open(backupDir .. filename, "r")
	ok1, pool   = serpent.load(file:read("*line"))
	ok2, levels = serpent.load(file:read("*line"))
	ok3, clients = serpent.load(file:read("*line"))
	file:close()

	-- Make sure all levels fields have been initialized
	clearLevels()
	
	-- Find the next unmeasured genome
	while fitnessAlreadyMeasured() do
		nextGenome()
	end
	initializeRun()
	pool.currentFrame = pool.currentFrame + 1
end

writeFile("temp.pool")
clearLevels()

printf = function(s,...)
           return io.write(s:format(...))
         end -- function

function printBanner(percentage)
	-- Print previous results
	bannerscr:mvaddstr(1,1,string.format("      gen %3d species %3d genome %3d (%3.1f%%)",   last_generation,
																					last_species,
																					last_genome,
																					percentage))
	bannerscr:mvaddstr(2,1,string.format("       fitness: %6d  max fitness: %6d", math.floor(lastSumFitness),
																					math.floor(pool.maxFitness)))
	bannerscr:refresh()
end

-- TODO: This assumes those that requested it also checked it in. 
function printGenomeDisplay()
	local jobIndex = 1
	genomescr:move(1,1)
	for r = 1, NUM_DISPLAY_ROWS do
		for c = 1, NUM_DISPLAY_COLS do
			local job = jobs[jobIndex]
			-- Is the job finished?
			if pool.species[job.species].genomes[job.genome].fitness ~= 0 then
				genomescr:attron(curses.color_pair(1))
				if job.client then	
					genomescr:addch(job.client)
				else
					genomescr:addch("#")
				end
				genomescr:attroff(curses.color_pair(1))
			else
				-- Requested?
				if job.requested then
					if job.client then
						genomescr:addch(job.client)
					else
						genomescr:addch("o")
					end
				else
					genomescr:addch(" ")
				end
			end
			jobIndex = jobIndex + 1
		end
		y, x = genomescr:getyx()
		genomescr:move(y+1, 1)
	end
	genomescr:refresh()
end

function getHistoBuckets(avgs, num_buckets, max_per_bucket)
	buckets = {}
	for i = 1, num_buckets do
		buckets[i] = 0
	end

	local total = 0
	for k, v in pairs(avgs) do
		if v ~= 0 then
			total = total + 1
			local index =  math.floor((v + 5000) / 10000)
			if index > 0 and index <= #buckets then
				buckets[index] = buckets[index] + 1
			end
		end
	end

	for i = 1, num_buckets do
		-- Round
		buckets[i] = math.floor((buckets[i] / total) * max_per_bucket + 0.5)
	end

	return buckets
end

function printHistoDisplay()
	local num_buckets = 50
	local max_per_bucket = histoscrheight - 4
	local buckets = getHistoBuckets(fitnessAverages, num_buckets, histoscrheight - 5)

	-- Add values
	for x = 1, num_buckets do
		for y = 1, max_per_bucket do
			if max_per_bucket - y <= buckets[x] then
				histoscr:attron(curses.color_pair(3))
				histoscr:mvaddch(y, x, " ")
				histoscr:attroff(curses.color_pair(3))
			end
		end
	end

	-- Axis labelling
	local y_hist = histoscrheight-4
	for x=1,num_buckets do
		if x % 5 == 0 then
			histoscr:mvaddstr(y_hist,x,"+")
		else
			histoscr:mvaddstr(y_hist,x,"-")
		end

		if x % 5 == 0 then
			if x == 5 then
				histoscr:mvaddstr(y_hist+1,x,tostring(x))
			else
				histoscr:mvaddstr(y_hist+1,x-1,tostring(x))
			end
		end
		histoscr:mvaddstr(histoscrheight-2,8,string.format("(10 = 100k)    average: %6.2f", getAverage(fitnessAverages)))
		histoscr:refresh()
	end
end

function printLevelsDisplay()
	-- Don't print levels until we have results.
	if not last_levels then
		return
	end
	levelscr:mvaddstr(1,3,"lvl | times beaten  | reason     | fitness")
	for i=1, #last_levels do
		local world, level = getWorldAndLevel(i)
		-- active for compatibility

		local y, x = levelscr:getyx()

		if last_levels[i].a or last_levels[i].active then
			if last_levels[i].f and last_levels[i].f > 0 then
				if last_levels[i].r == "victory" then
					levelscr:attron(curses.color_pair(1))
				end
				if last_levels[i].r == "enemyDeath" then
					levelscr:attron(curses.color_pair(2))
				end
				levelscr:mvaddstr(y+1,1,string.format("  %1d-%1d | %13d | %10s |    %10.2f", world,
																							level,
																							levels[i].timesWon,
																							last_levels[i].r,
																							calculateFitness(last_levels[i], i)))

				levelscr:attroff(curses.color_pair(1))
				levelscr:attroff(curses.color_pair(2))
			else
				levelscr:mvaddstr(y+1,1,string.format("  %1d-%1d | %13s |            |", world,
																									  level,
																									  "todo"))
			end
		else
			--[[
			local fill = "-------------------------------------------------------"
			-- Castle levels get special treatment
			if i % 4 ~= 0 then
				fill = "             Oo~Oo~Oo~Oo~Oo~Oo~             "
			else -- Otherwise, assume water
				fill = "______________[^]__[^__^]__[^]______________"
			end
			levelscr:mvaddstr(y+1,1,string.format("  %1d-%1d |%30s", world, level, fill))
			]]--
		end
	end
	levelscr:refresh()
end

function printClientsDisplay()
	clientscr:mvaddstr(1,1," a | id       client | genomes       | frames     | stale")
	local totalLevelsPlayed = 0
	for client, stats in pairs(clients) do
		totalLevelsPlayed = totalLevelsPlayed + stats.levelsPlayed
	end
	local now = socket.gettime()
	for client, stats in pairs(clients) do
		-- Temporary. Can be deleted once all clients have IDs.
		if not stats.char then
			stats.char = nextClientChar(clients)
		end

		local percent = (stats.levelsPlayed / totalLevelsPlayed) * 100
		active = ""
		if isFreshClient(client, now) then
			active = "*"
		end
		local y, x = clientscr:getyx()
		clientscr:mvaddstr(y+1,1,string.format(" %1s | %1s %13s | %7d %4.1f%% | %10d | %5d",
			active, stats.char, client, stats.levelsPlayed, percent, stats.framesPlayed, stats.staleLevels))
	end
	clientscr:refresh()
end

function printBoard(percentage)
	printClientsDisplay()
	printLevelsDisplay()
	printBanner(percentage)
	printGenomeDisplay()
	printHistoDisplay()
end

------------------------------- Averages --------------------------------
-- Keep track of the last N values to keep a rolling average

-- It's a good idea to keep these in sync with SAVE_EVERY (or divisible by)
local TimeAverageSize = 100
local FramesAverageSize = 100
local NumPortSize = 16
local FitnessAverageSize = Population

function createAverage(size)
	averages = {}
	for z = 1, size do
		averages[z] = 0
	end
	averages.index = 1
	return averages
end

function addAverage(averages, value)
	averages[averages.index] = value
	averages.index = averages.index + 1
	if averages.index > #averages then
		averages.index = 1
	end
end

function getAverage(averages)
	local total = 0
	local num = 0
	for key, value in pairs(averages) do
		if key ~= "index" and value ~= 0 then
			total = total + value
			num = num + 1
		end
	end
	return total / num
end

timeAverages = createAverage(TimeAverageSize)
frameAverages = createAverage(FramesAverageSize)
fitnessAverages = createAverage(FitnessAverageSize)

--------------------------- End averages --------------------------------

function calculateFitness(level, stateIndex)
	local result = level.d
	local timePenalty = level.f / 10
	if level.w == 1 then
		result = result + 5000
	end

	local world, level = getWorldAndLevel(stateIndex)
	local multi = 1.0 + (WorldAugmenter*world) + (LevelAugmenter*level)

	return 100 + (multi * result) - timePenalty
end

function calculateTotalFitness(levels)
	local total = 0
	for stateIndex, level in pairs(levels) do
		if level.a then
			total = total + calculateFitness(level, stateIndex)
		end
	end
	return total
end

function calculatePercentage()
	-- Calculating percent of generation done
	local measured = 0
	local total = 0
	for _,species in pairs(pool.species) do
		for _,genome in pairs(species.genomes) do
			total = total + 1
			if genome.fitness ~= 0 then
				measured = measured + 1
			end
		end
	end
	return (measured / total) * 100
end

function sumFrames(lvls)
	local totalFrames = 0
	for i = 1, #lvls do
		totalFrames = totalFrames + lvls[i].f
	end
	return totalFrames
end

function addVictories(results)
	for i = 1, #results do
		if results[i].r == "victory" then
			levels[i].timesWon = levels[i].timesWon + 1
		end
	end
end

function isFreshClient(clientId, now)
	if clients[clientId].lastCheckIn then
		return now - clients[clientId].lastCheckIn < 60
	end
	return false
end

function nextClientChar(clients)
	max = string.byte('a') - 1
	for clientId, stats in pairs(clients) do
		cur = stats.char
		if cur and string.byte(cur) > max then
			max = string.byte(cur)
		end
	end
	return string.char(max + 1)
end

function sendStaleMsgToAllClients()
	-- Send a warning messaage
	local now = socket.gettime()
	local row = 12
	for clientId, stats in pairs(clients) do
		if isFreshClient(clientId, now) and stats.ip and stats.ports then
			for p= 1,#stats.ports do
				local p = stats.ports[p]
				if p then
					--clientscr:mvaddstr(row,1,string.format("sending stale msg to %s %d", stats.ip, p))
					row = row + 1
					ok, err = udp:sendto("1\n", stats.ip, p)
					clientscr:refresh()
				end
			end
		end
	end
end

-- Load backup if provided
if #arg > 0 then
	--print("Loading backup: " .. arg[1])
	loadFile(arg[1])
end

-- The last generation we saved
lastGenerationSaved = pool.generation

pool.currentSpecies = 1
pool.currentGenome = 1

-- Connection stats
local connectionCount = 0
local totalTimeWaiting = 0
local totalTimeCommunicating = 0

-- Global so we can print the last result easily
last_levels = nil
last_generation = -1
last_species = -1
last_genome = -1
lastSumFitness = 0

-- Used for the average FPS over the total session
local start_of_session = socket.gettime()
local total_frames_session = 0

while true do
	local percentage = calculatePercentage()
	local startTime = socket.gettime()

	local startTimeWaiting = socket.gettime()
	local client = server:accept()
	totalTimeWaiting = totalTimeWaiting + (socket.gettime() - startTimeWaiting)
	connectionCount = connectionCount + 1

	-- Receive the line
	local startTimeCommunicating = socket.gettime()
	local line, err = client:receive()

	local stop_sending_levels = false

	-- Was it good?
	if not err then
		toks = mysplit(line, "!")

		clientId = toks[1]

		-- Remember client ip and port if they are a known client
		local client_ip, client_port = client:getpeername()
		if clients[clientId] then
			clients[clientId].ip = client_ip
			if not clients[clientId].ports then
				clients[clientId].ports = createAverage(NumPortSize)
			end
			addAverage(clients[clientId].ports, tonumber(client_port))
			clients[clientId].lastCheckIn = socket.gettime()
		end

		if #toks > 2 then
			local r_generation = tonumber(toks[2])
			local r_species = tonumber(toks[3])
			local r_genome = tonumber(toks[4])
			local iterationId = tonumber(toks[5])
			local versionCode = tonumber(toks[6])
			local ok, r_levels = serpent.load(toks[7])
			stop_sending_levels = toks[8]

			-- Is this a new client?
			if not clients[clientId] then
				clients[clientId] = {
					levelsPlayed = 0,
					framesPlayed = 0,
					staleLevels = 0,
					lastCheckIn = 0,
					char = nextClientChar(clients)}
			end

			-- Only use fresh results from new clients (if we haven't already received this result)
			if r_generation == pool.generation
				and iterationId == iteration
				and versionCode == VERSION_CODE
				and pool.species[r_species].genomes[r_genome].fitness == 0 then

				local fitnessResult = calculateTotalFitness(r_levels)
				lastSumFitness = fitnessResult
				pool.species[r_species].genomes[r_genome].fitness = fitnessResult
				addAverage(fitnessAverages, lastSumFitness)

				if fitnessResult > pool.maxFitness then
					writeGenome(tostring(fitnessResult) .. ".genome", pool.species[r_species].genomes[r_genome])
				end

				local totalFrames = sumFrames(r_levels)
				addAverage(frameAverages, totalFrames)
				total_frames_session = total_frames_session + totalFrames

				addVictories(r_levels)

				-- Update client stats
				clients[clientId].levelsPlayed = clients[clientId].levelsPlayed + 1
				clients[clientId].framesPlayed = clients[clientId].framesPlayed + totalFrames

				last_levels = r_levels
				last_generation = r_generation
				last_species = r_species
				last_genome = r_genome
				last_network = pool.species[r_species].genomes[r_genome].network
			else
				-- Didn't make it in time--update stale counter
				clients[clientId].staleLevels = clients[clientId].staleLevels + 1
			end
		end

		-- Send the next network to play
		-- TODO: one table to rule them all
		if stop_sending_levels ~= "true" then
			-- Find the first open, non-requested spot.
			-- Sets currentSpecies / currentGenome to a requested spot if all have been requested.
			findNextNonRequestedGenome()
			initializeRun()
			local species = pool.species[pool.currentSpecies]
			local genome = species.genomes[pool.currentGenome]

			local response = serpent.dump(levels) .. "!" 
							.. iteration .. "!" 
							.. pool.generation .. "!" 
							.. pool.currentSpecies .. "!" 
							.. pool.currentGenome .. "!" 
							.. math.floor(pool.maxFitness) .. "!" 
							.. "(" .. percentage .. "%)!"
							.. serpent.dump(genome.network) .. "\n"
			--levels[nextLevel].lastRequester = clientId
			client:send(response)
			genome.last_requested = pool.generation

			-- Set client char if available
			if clients[clientId] then
				jobs[jobs.index].client = clients[clientId].char
			end
		end

		totalTimeCommunicating = totalTimeCommunicating + (socket.gettime() - startTimeCommunicating)
	else
		--print("Error: " .. err)
	end

	-- done with client, close the object
	client:close()

	printBoard(percentage)

	-- Make backups if we beat the current best	
	if lastSumFitness > pool.maxFitness then
		pool.maxFitness = lastSumFitness
		writeFile("backup." .. last_generation .. ".NEW_BEST")
		writeNetwork("backup_network.fitness" .. pool.maxFitness .. ".gen" .. last_generation .. ".genome" .. last_genome .. ".species" .. last_species .. ".NEW_BEST", last_network)
	end

	-- TODO remove if we don't ever want this (or do time based, e.g. every 20 mins)
	-- if lastSaved >= SAVE_EVERY then
	-- 	writeFile("backup.checkpoint")
	-- 	lastSaved = 0
	-- 	lastCheckpoint = os.date("%c", os.time())
	-- end

	-- Save a backup of the generation
	if lastGenerationSaved + SAVE_EVERY_N_GENERATIONS < pool.generation then
		writeFile("backup." .. pool.generation .. "." .. "NEW_GENERATION")
		lastGenerationSaved = pool.generation
	end

	local endTime = socket.gettime()

	addAverage(timeAverages, endTime - startTime)
	local averageTime = getAverage(timeAverages)
	local frameAverage = getAverage(frameAverages)
	statscr:mvaddstr(1,1,string.format("   last: %5.3f", endTime - startTime))
	statscr:mvaddstr(2,1,string.format("average: %5.3f", averageTime))
	statscr:mvaddstr(3,1,string.format("frames played per second   (avg): %7.0f",
		frameAverage / averageTime))
	statscr:mvaddstr(4,1,string.format("frames played per second (total): %7.0f",
		total_frames_session / (endTime - start_of_session)))
	statscr:mvaddstr(5,1,string.format("%2d conns | %5.3fs waiting | %5.3fs comm",
		connectionCount, totalTimeWaiting, totalTimeCommunicating))
	if lastCheckpoint then
		statscr:mvaddstr(6,1,"last saved: " .. lastCheckpoint)
	end
	statscr:refresh()
end
