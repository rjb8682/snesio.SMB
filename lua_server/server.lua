local serpent = require("serpent")
local socket = require("socket")
local server = assert(socket.bind("*", 56507))
local ip, port = server:getsockname()

---- Set up curses
local curses = require("curses")
curses.initscr()
curses.cbreak()
curses.echo(false)
curses.nl(false)
local stdscr = curses.stdscr()
stdscr:clear()
curses.start_color()
curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK);
curses.init_pair(2, curses.COLOR_RED, curses.COLOR_BLACK);
-----------------

-- The number of genomes we've run through (times all levels have been played)
iteration = 0

-- Increment this when breaking changes are made (will cause old clients to be ignored)
local VERSION_CODE = 4

-- New field: totalFrames. TODO: consider using average frames over the last 100
-- iterations for example. May not be worth the extra work, honestly. Even easier
-- is resetting totalFrames every so often for a similar effect.
levels = {
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 1-1
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 1-2
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 1-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}, -- 1-4, castle
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 2-1
	{fitness = nil, totalFrames = 0, active = false, kind = "water"}, -- 2-2, water level
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 2-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}, -- 2-4, castle
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 3-1
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 3-2
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 3-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}, -- 3-4, castle
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 4-1
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 4-2
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 4-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}, -- 4-4, castle
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 5-1
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 5-2,
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 5-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}, -- 5-4, castle
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 6-1
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 6-2
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 6-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}, -- 6-4, castle
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 7-1
	{fitness = nil, totalFrames = 0, active = false, kind = "water"}, -- 7-2, water level
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 7-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}, -- 7-4, castle
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 8-1
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 8-2
	{fitness = nil, totalFrames = 0, active = true, kind = "land"},  -- 8-3
	{fitness = nil, totalFrames = 0, active = false, kind = "castle"}  -- 8-4, castle
}

levelIndex = 1

function nextUnfinishedLevel()
	local i = levelIndex
	--print("levelIndex: " .. levelIndex)

	for _ = 1, #levels do
		-- Modify the order based on how long each level is
		level = orderedLevels[i].index

		if levels[level].active and levels[level].fitness == nil then
			levelIndex = (i % #levels)
			return level
		end

		i = (i % #levels) + 1
	end

	return nil
end

function clearLevels()
	for i = 1, #levels, 1 do
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

Filename = "1.State"
ButtonNames = {
	"A",
	--"B",
	--"Up",
	--"Down",
	"Left",
	"Right",
}

BoxRadius = 6
InputSize = (BoxRadius*2+1)*(BoxRadius*2+1) -- marioVX, marioVY

Inputs = InputSize + 3
Outputs = #ButtonNames

compoundDistanceTraveled = 0

Population = 300
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

TimeoutConstant = 20

WorldAugmenter = 0.2
LevelAugmenter = 0.1

MaxNodes = 1000000

wonLevel = false

-- deleted getPositions

-- deleted getTile

-- deleted getSprites

-- deleted getExtendedSprites

-- deleted getInputs()

function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end

function newInnovation()
	pool.innovation = pool.innovation + 1
	return pool.innovation
end

function newPool()
	print("CALLING NEWPOOL")
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

function evaluateNetwork(network, inputs)
	table.insert(inputs, 1)

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
			neuron.value = sigmoid(sum)
		end
	end
	
	local outputs = {}
	for o=1,Outputs do
		local button = "P1 " .. ButtonNames[o]
		if network.neurons[MaxNodes+o].value > 0 then
			outputs[button] = true
		else
			outputs[button] = false
		end
	end
	
	return outputs
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

function newGeneration()
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
	
	--print("writing backup file in newGeneration")
	writeFile("backup." .. pool.generation .. "." .. "NEW_GENERATION")
end
	
function initializePool()
	print("initializePool")
	pool = newPool()

	for i=1,Population do
		basic = basicGenome()
		addToSpecies(basic)
	end

	initializeRun()
end

-- deleted clearJoypad

function initializeRun()
	-- savestate.load(Filename);
	-- rightmost = 0
	-- pool.currentFrame = 0
	-- timeout = TimeoutConstant
	-- clearJoypad()
	
	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]
	generateNetwork(genome)
	--evaluateCurrent()
end

-- deleted evaluateCurrent

print("is pool nil?")
if pool == nil then
	print("yup")
	initializePool()
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

-- deleted displayGenome (genome)

function writeFile(filename)
    local file = io.open("backups/" .. filename, "w")
	file:write(pool.generation .. "\n")
	file:write(pool.maxFitness .. "\n")
	file:write(#pool.species .. "\n")
        for n,species in pairs(pool.species) do
		file:write(species.topFitness .. "\n")
		file:write(species.staleness .. "\n")
		file:write(#species.genomes .. "\n")
		for m,genome in pairs(species.genomes) do
			file:write(genome.fitness .. "\n")
			file:write(genome.maxneuron .. "\n")
			for mutation,rate in pairs(genome.mutationRates) do
				file:write(mutation .. "\n")
				file:write(rate .. "\n")
			end
			file:write("done\n")
			
			file:write(#genome.genes .. "\n")
			for l,gene in pairs(genome.genes) do
				file:write(gene.into .. " ")
				file:write(gene.out .. " ")
				file:write(gene.weight .. " ")
				file:write(gene.innovation .. " ")
				if(gene.enabled) then
					file:write("1\n")
				else
					file:write("0\n")
				end
			end
		end
        end
        file:close()
end

function writeNetwork(filename, network)
    local file = io.open("backups/networks/" .. filename, "w")
	file:write(serpent.dump(network))
	file:write("\n")
    file:close()
end

function loadNetwork(filename)
	local file = io.open("backups/networks/" .. filename, "r")
	local network = serpent.load(file:read("*line"))
	file:close()
	return network
end

function savePool()
	local filename = "SERVER_BACKUP_3" 
	print("writing file in savePool")
	writeFile(filename)
end

function loadFile(filename)
	print("CALLING LOADFILE")
    local file = io.open("backups/" .. filename, "r")
	pool = newPool()
	pool.generation = file:read("*number")
	pool.maxFitness = file:read("*number")
	--forms.settext(maxFitnessLabel, "Max Fitness: " .. math.floor(pool.maxFitness))
    local numSpecies = file:read("*number")
    for s=1,numSpecies do
		local species = newSpecies()
		table.insert(pool.species, species)
		species.topFitness = file:read("*number")
		species.staleness = file:read("*number")
		local numGenomes = file:read("*number")
		for g=1,numGenomes do
			local genome = newGenome()
			table.insert(species.genomes, genome)
			genome.fitness = file:read("*number")
			genome.maxneuron = file:read("*number")
			local line = file:read("*line")
			while line ~= "done" do
				genome.mutationRates[line] = file:read("*number")
				line = file:read("*line")
			end
			local numGenes = file:read("*number")
			for n=1,numGenes do
				local gene = newGene()
				table.insert(genome.genes, gene)
				local enabled
				gene.into, gene.out, gene.weight, gene.innovation, enabled = file:read("*number", "*number", "*number", "*number", "*number")
				if enabled == 0 then
					gene.enabled = false
				else
					gene.enabled = true
				end
				
			end
		end
	end
    file:close()
	
	while fitnessAlreadyMeasured() do
		nextGenome()
	end
	initializeRun()
	pool.currentFrame = pool.currentFrame + 1
end
 
function loadPool()
	--local filename = forms.gettext(saveLoadFile)
	--loadFile(filename)
end

function playTop()
	local maxfitness = 0
	local maxs, maxg
	for s,species in pairs(pool.species) do
		for g,genome in pairs(species.genomes) do
			if genome.fitness > maxfitness then
				maxfitness = genome.fitness
				maxs = s
				maxg = g
			end
		end
	end
	
	pool.currentSpecies = maxs
	pool.currentGenome = maxg
	pool.maxFitness = maxfitness
	initializeRun()
	pool.currentFrame = pool.currentFrame + 1
	return
end

function resetMaxFitness()
	pool.maxFitness = 0
end

print("writing temp.pool")
writeFile("temp.pool")

-- deleted playGame

printf = function(s,...)
           return io.write(s:format(...))
         end -- function


lastSumFitness = 0
function printBoard()
	-- Print previous results
	stdscr:mvaddstr(0,0,"####################################################\n")
	stdscr:addstr(string.format("#  gen %3d species %3d genome %3d fitness: %6d  #\n",  pool.generation,
																					    pool.currentSpecies,
																						pool.currentGenome,
																						math.floor(lastSumFitness)))
	stdscr:addstr(string.format("#               max fitness: %6d                #\n", math.floor(pool.maxFitness)))
	stdscr:addstr("####################################################\n")

	stdscr:addstr(string.format("| lvl | client        | reason     | fitness       |\n", i))
	for i=1, #levels do
		local world, level = getWorldAndLevel(i)
		if levels[i].active then
			if levels[i].fitness then
				if levels[i].reason == "victory" then
					stdscr:attron(curses.color_pair(1))
				end
				if levels[i].reason == "enemyDeath" then
					stdscr:attron(curses.color_pair(2))
				end
				stdscr:addstr(string.format("| %1d-%1d | %13s | %10s |    %10.2f | %10d\n", world, level, levels[i].lastRequester, levels[i].reason, levels[i].fitness, levels[i].totalFrames))

				stdscr:attroff(curses.color_pair(1))
				stdscr:attroff(curses.color_pair(2))

			else
				stdscr:addstr(string.format("| %1d-%1d | %13s |            |               | %10d\n", world, level, levels[i].lastRequester, levels[i].totalFrames))
			end
		else
			local fill = "-------------------------------------------------------"
			if levels[i].kind == "water" then
				fill = "            Oo~Oo~Oo~Oo~Oo~Oo~              "
			else
				if levels[i].kind == "castle" then
					fill = "______________[^]__[^__^]__[^]______________"
				end
			end
			stdscr:addstr(string.format("| %1d-%1d |%30s|\n", world, level, fill))
		end
	end
	stdscr:refresh()
end

-- Returns an ordering through a table based on the totalFrames field
function genOrderedIndex( t )
    local orderedIndex = {}
    for key, value in pairs(t) do
        table.insert( orderedIndex, {index=key, t=value})
    end
    table.sort( orderedIndex, function(a, b) return a.t.totalFrames > b.t.totalFrames end)
    --[[
    for key,value in pairs(orderedIndex) do
    	stdscr:addstr("[" .. key .. ":" .. value.t.totalFrames .. ":" .. value.index .. "] ")
    end
    stdscr:refresh()
    ]]--
    return orderedIndex
end

function calculateFitness(distance, frames, wonLevel, reason, stateIndex)
	local result = distance
	local timePenalty = frames / 10
	if wonLevel == 1 then
		result = result + 5000
	end

	local world, level = getWorldAndLevel(stateIndex)
	local multi = 1.0 + (WorldAugmenter*world) + (LevelAugmenter*level)

	return 100 + (multi * result) - timePenalty
end

-- loop forever waiting for clients
function getFitness(species, genome)
	clearLevels()
	local nextLevel = nextUnfinishedLevel()
	while true do

		-- Is this generation complete?
		if nextLevel == nil then
			-- Process results
			local result = sumFitness()

			-- Get new level
			nextLevel = nextUnfinishedLevel()

			-- Clear generation. Resets fitness + levelIndex + increments iterationId
			clearLevels()

			-- We're done!
			return result
		end

		-- Not done. Wait for a connection from any client
		local client = server:accept()
		-- Receive the line
		local line, err = client:receive()

		-- Was it good?
		if not err then

			toks = mysplit(line, "!")

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

			clientId = toks[1]

			if #toks > 1 then
				stateIndex = tonumber(toks[2])
				iterationId = tonumber(toks[3])
				distance = tonumber(toks[4])
				frames = tonumber(toks[5])
				wonLevel = tonumber(toks[6])
				reason = toks[7]
				versionCode = tonumber(toks[8])

				fitnessResult = calculateFitness(distance, frames, wonLevel, reason, stateIndex)

				-- Only use fresh results from new clients
				if iterationId == iteration and versionCode == VERSION_CODE then
					levels[stateIndex].fitness = fitnessResult
					levels[stateIndex].totalFrames = levels[stateIndex].totalFrames + frames
					levels[stateIndex].lastRequester = clientId
					levels[stateIndex].reason = reason
				end
			end

			-- Since we got a request, advance to the next level.
			nextLevel = nextUnfinishedLevel()
			if nextLevel then
				local response = nextLevel .. "!" 
								.. iteration .. "!" 
								.. pool.generation .. "!" 
								.. pool.currentSpecies .. "!" 
								.. pool.currentGenome .. "!" 
								.. math.floor(pool.maxFitness) .. "!" 
								.. "(" .. math.floor(measured/total*100) .. "%)!"
								.. serpent.dump(genome.network) .. "\n"
				--print("REQUEST: " .. nextLevel)
				levels[nextLevel].lastRequester = clientId
				client:send(response)
			else 
				client:send("no_level")
			end
			printBoard()
		else
			print("Error: " .. err)
		end

		-- done with client, close the object
		client:close()
	end
end

-- Load backup if provided
if #arg > 0 then
	print("Loading backup: " .. arg[1])
	loadFile(arg[1])
end

-- How many iterations to wait before saving a checkpoint
SAVE_EVERY = 5
-- How many iterations ago we last saved
lastSaved = 999

while true do

	initializeRun()

	-- Sort the levels based on the total frames spent on each level.
	-- (long levels get played first for optimal scheduling)
	orderedLevels = genOrderedIndex(levels)

	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]

	-- This calls the clients
	local startTime = os.time()
	local fitness = getFitness(species, genome)
	local endTime = os.time()

	lastSumFitness = fitness
	genome.fitness = fitness
	
	-- Make backups if we beat the current best	
	if fitness > pool.maxFitness then
		pool.maxFitness = fitness
		--forms.settext(maxFitnessLabel, "Max Fitness: " .. math.floor(pool.maxFitness))
		writeFile("backup." .. pool.generation .. ".NEW_BEST")
		writeNetwork("backup_network.fitness" .. pool.maxFitness .. ".gen" .. pool.generation .. ".genome" .. pool.currentGenome .. ".species" .. pool.currentSpecies .. ".NEW_BEST", genome.network)
	end

	-- Save a checkpoint if necessary
	lastSaved = lastSaved + 1
	
	if lastSaved >= SAVE_EVERY then
		writeFile("backup.checkpoint")
		lastSaved = 0
		lastCheckpoint = os.date("%c", os.time())
	end

	stdscr:addstr("took " .. (endTime - startTime) .. " seconds\n")
	stdscr:addstr("saved last checkpoint at " .. lastCheckpoint)
	-- Refresh to show the iteration time + our last checkpoint	
	stdscr:refresh()

	pool.currentSpecies = 1
	pool.currentGenome = 1
	while fitnessAlreadyMeasured() do
		nextGenome()
	end
end
