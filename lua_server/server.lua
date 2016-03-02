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
local VERSION_CODE = 7

-- New field: totalFrames. TODO: consider using average frames over the last 100
-- iterations for example. May not be worth the extra work, honestly. Even easier
-- is resetting totalFrames every so often for a similar effect.
levels = {
	{active = true, kind = "land"},  -- 1-1
	{active = true, kind = "land"},  -- 1-2
	{active = true, kind = "land"},  -- 1-3
	{active = false, kind = "castle"}, -- 1-4, castle
	{active = true, kind = "land"},  -- 2-1
	{active = false, kind = "water"}, -- 2-2, water level
	{active = true, kind = "land"},  -- 2-3
	{active = false, kind = "castle"}, -- 2-4, castle
	{active = true, kind = "land"},  -- 3-1
	{active = true, kind = "land"},  -- 3-2
	{active = true, kind = "land"},  -- 3-3
	{active = false, kind = "castle"}, -- 3-4, castle
	{active = true, kind = "land"},  -- 4-1
	{active = true, kind = "land"},  -- 4-2
	{active = true, kind = "land"},  -- 4-3
	{active = false, kind = "castle"}, -- 4-4, castle
	{active = true, kind = "land"},  -- 5-1
	{active = true, kind = "land"},  -- 5-2,
	{active = true, kind = "land"},  -- 5-3
	{active = false, kind = "castle"}, -- 5-4, castle
	{active = true, kind = "land"},  -- 6-1
	{active = true, kind = "land"},  -- 6-2
	{active = true, kind = "land"},  -- 6-3
	{active = false, kind = "castle"}, -- 6-4, castle
	{active = true, kind = "land"},  -- 7-1
	{active = false, kind = "water"}, -- 7-2, water level
	{active = true, kind = "land"},  -- 7-3
	{active = false, kind = "castle"}, -- 7-4, castle
	{active = true, kind = "land"},  -- 8-1
	{active = true, kind = "land"},  -- 8-2
	{active = true, kind = "land"},  -- 8-3
	{active = false, kind = "castle"}  -- 8-4, castle
}

-- This table keeps track of how many results + frames each client has returned
-- This only increments when a client is the *first* to return a level's result
clients = {}

-- Keep track of the last TimeAverageSize times to keep a rolling average
TimeAverageSize = 100
timeAverageIndex = 1
timeAverages = {}
for z = 1, TimeAverageSize do
	timeAverages[z] = 0
end

function clearLevels()
	for i = 1, #levels, 1 do
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

Population = 10
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

function findNextNonRequestedGenome()
	pool.currentSpecies = 1
	pool.currentGenome = 1
	local genome = pool.species[pool.currentSpecies].genomes[pool.currentGenome]

	-- Advance past all requested and measured species.
	while genome.fitness ~= 0 or genome.last_requested == pool.generation do
		print(pool.currentSpecies .. " " .. pool.currentGenome)
		pool.currentGenome = pool.currentGenome + 1
		if pool.currentGenome > #pool.species[pool.currentSpecies].genomes then
			pool.currentGenome = 1
			pool.currentSpecies = pool.currentSpecies + 1
			if pool.currentSpecies > #pool.species then
				-- There were no un-requested genomes.
				-- Do the normal loop instead (may trigger new generation)
				pool.currentSpecies = 1
				while fitnessAlreadyMeasured() do
					nextGenome()
				end
				return
			end
		end
		genome = pool.species[pool.currentSpecies].genomes[pool.currentGenome]
	end
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
	-- local file = io.open("backups/" .. filename, "w")
	-- file:write(serpent.dump(pool))
	-- file:write("\n")
	-- file:write(serpent.dump(levels))
	-- file:write("\n")
	-- file:write(serpent.dump(clients))
 --        file:close()
end

function writeNetwork(filename, network)
	-- TODO: turn on when ready
	-- local file = io.open("backups/networks/" .. filename, "w")
	-- file:write(serpent.dump(network))
	-- file:write("\n")
	-- file:close()
end

function loadFile(filename)
	local file = io.open("backups/" .. filename, "r")
	ok1, pool   = serpent.load(file:read("*line"))
	ok2, levels = serpent.load(file:read("*line"))
	ok3, clients = serpent.load(file:read("*line"))
	file:close()
	
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


lastSumFitness = 0
function printBoard(percentage)
	-- Print previous results
	stdscr:mvaddstr(0,0,"####################################################\n")
	stdscr:addstr(string.format("#      gen %3d species %3d genome %3d (%3.1f%%)      #\n",   pool.generation,
																					pool.currentSpecies,
																					pool.currentGenome,
																					percentage))
	stdscr:addstr(string.format("#       fitness: %6d  max fitness: %6d       #\n", math.floor(lastSumFitness),
																					math.floor(pool.maxFitness)))
	stdscr:addstr("####################################################\n")

	stdscr:addstr(string.format("| lvl | client        | reason     | fitness       |\n", i))
	if not last_levels then
		return
	end
	for i=1, #last_levels do
		local world, level = getWorldAndLevel(i)
		if last_levels[i].active then
			if last_levels[i].frames > 0 then
				if last_levels[i].reason == "victory" then
					stdscr:attron(curses.color_pair(1))
				end
				if last_levels[i].reason == "enemyDeath" then
					stdscr:attron(curses.color_pair(2))
				end
				stdscr:addstr(string.format("| %1d-%1d | %13s | %10s |    %10.2f | %5d ~ %8d\n", world,
																							level,
																							last_levels[i].lastRequester,
																							last_levels[i].reason,
																							calculateFitness(last_levels[i], i),
																							last_levels[i].timesWon,
																							last_levels[i].totalFrames))

				stdscr:attroff(curses.color_pair(1))
				stdscr:attroff(curses.color_pair(2))

			else
				stdscr:addstr(string.format("| %1d-%1d | %13s |            |               | %5d ~ %8d\n", world,
																									  level,
																									  last_levels[i].lastRequester,
																									  last_levels[i].timesWon,
																									  last_levels[i].totalFrames))
			end
		else
			local fill = "-------------------------------------------------------"
			if last_levels[i].kind == "water" then
				fill = "             Oo~Oo~Oo~Oo~Oo~Oo~             "
			else
				if last_levels[i].kind == "castle" then
					fill = "______________[^]__[^__^]__[^]______________"
				end
			end
			stdscr:addstr(string.format("| %1d-%1d |%30s|\n", world, level, fill))
		end
	end

	stdscr:addstr("\n       --------------------------------------------\n")
	stdscr:addstr("      | client        | levels        | frames     | stale\n")
	local totalLevelsPlayed = 0
	for client, stats in pairs(clients) do
		totalLevelsPlayed = totalLevelsPlayed + stats.levelsPlayed
	end
	for client, stats in pairs(clients) do
		local percent = (stats.levelsPlayed / totalLevelsPlayed) * 100
		stdscr:addstr(string.format("      | %13s | %7d %4.1f%% | %10d | %7d", client, stats.levelsPlayed, percent, stats.framesPlayed, stats.staleLevels))
		stdscr:addstr("\n")
	end
	stdscr:addstr("       --------------------------------------------\n\n")
	stdscr:refresh()
end

function addTimeAverage(time)
	timeAverages[timeAverageIndex] = time
	timeAverageIndex = timeAverageIndex + 1
	if timeAverageIndex > TimeAverageSize then
		timeAverageIndex = 1
	end
end

function getAverageTime()
	local totalTime = 0
	local numTimes = 0
	for key, value in pairs(timeAverages) do
		totalTime = totalTime + value
		if value > 0 then numTimes = numTimes + 1 end
	end
	return totalTime / numTimes
end

function calculateFitness(level, stateIndex)
	local result = level.dist
	local timePenalty = level.frames / 10
	if level.wonLevel == 1 then
		result = result + 5000
	end

	local world, level = getWorldAndLevel(stateIndex)
	local multi = 1.0 + (WorldAugmenter*world) + (LevelAugmenter*level)

	return 100 + (multi * result) - timePenalty
end

function calculateTotalFitness(levels)
	local sumFitness = 0
	for stateIndex, level in pairs(levels) do
		if level.active then
			sumFitness = sumFitness + calculateFitness(level, stateIndex)
		end
	end
	return sumFitness
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
end

-- Load backup if provided
if #arg > 0 then
	--print("Loading backup: " .. arg[1])
	loadFile(arg[1])
end

-- How many iterations to wait before saving a checkpoint
SAVE_EVERY = 100
-- How many iterations ago we last saved
lastSaved = 0

-- The last generation we saved
lastGenerationSaved = pool.generation

pool.currentSpecies = 1
pool.currentGenome = 1

lastSumFitness = 0

local connectionCount = 0
local totalTimeWaiting = 0
local totalTimeCommunicating = 0

-- Global so we can print the last result easily
last_levels = nil

while true do
	-- Find the first open, non-requested spot.
	-- Returns a requested spot if all have been requested.
	print("finding next genome!")
	findNextNonRequestedGenome()

	local startTime = socket.gettime()

	initializeRun()

	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]

	local startTimeWaiting = socket.gettime()
	local client = server:accept()
	totalTimeWaiting = totalTimeWaiting + (socket.gettime() - startTimeWaiting)
	connectionCount = connectionCount + 1

	-- Receive the line
	local startTimeCommunicating = socket.gettime()
	local line, err = client:receive()

	-- Was it good?
	if not err then
		toks = mysplit(line, "!")

		clientId = toks[1]

		if #toks > 2 then
			local r_generation = tonumber(toks[2])
			local r_species = tonumber(toks[3])
			local r_genome = tonumber(toks[4])
			local iterationId = tonumber(toks[5])
			local versionCode = tonumber(toks[6])
			local ok, r_levels = serpent.load(toks[7])

			-- Is this a new client?
			if not clients[clientId] then
				clients[clientId] = {levelsPlayed = 0, framesPlayed = 0, staleLevels = 0}	
			end

			-- Only use fresh results from new clients (if we haven't already received this result)
			if r_generation == pool.generation
				and iterationId == iteration
				and versionCode == VERSION_CODE
				and pool.species[r_species].genomes[r_genome].fitness == 0 then
				-- TODO process results function that does level stats etc
				local fitnessResult = calculateTotalFitness(r_levels)
				lastSumFitness = fitnessResult
				local r_genome = pool.species[r_species].genomes[r_genome]
				r_genome.fitness = fitnessResult

				-- Update client stats
				clients[clientId].levelsPlayed = clients[clientId].levelsPlayed + 1
				clients[clientId].framesPlayed = clients[clientId].framesPlayed + 0--TODO frames

				last_levels = r_levels
			else
				-- Didn't make it in time--update stale counter
				clients[clientId].staleLevels = clients[clientId].staleLevels + 1
			end
		end

		-- Send the next network to play
		-- TODO: one table to rule them all
		local response = serpent.dump(levels) .. "!" 
						.. iteration .. "!" 
						.. pool.generation .. "!" 
						.. pool.currentSpecies .. "!" 
						.. pool.currentGenome .. "!" 
						.. math.floor(pool.maxFitness) .. "!" 
						.. "(--%)!"
						.. serpent.dump(genome.network) .. "\n"
		--levels[nextLevel].lastRequester = clientId
		client:send(response)
		genome.last_requested = pool.generation

		totalTimeCommunicating = totalTimeCommunicating + (socket.gettime() - startTimeCommunicating)
	else
		--print("Error: " .. err)
	end

	-- done with client, close the object
	client:close()

	printBoard(0.0)
	
	-- Make backups if we beat the current best	
	if lastSumFitness > pool.maxFitness then
		pool.maxFitness = lastSumFitness
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

	-- Savea backup of the generation
	
	if lastGenerationSaved ~= pool.generation then
		writeFile("backup." .. pool.generation .. "." .. "NEW_GENERATION")
		lastGenerationSaved = pool.generation
	end

	local endTime = socket.gettime()

	addTimeAverage(endTime - startTime)
	stdscr:addstr(string.format("last: %5.3fs | average: %5.3fs ",
		endTime - startTime, getAverageTime()))

	stdscr:addstr(string.format("| %2d conns | %5.3fs waiting | %5.3fs communicating\n",
		connectionCount, totalTimeWaiting, totalTimeCommunicating))

	if lastCheckpoint then
		stdscr:addstr("\nsaved last checkpoint at " .. lastCheckpoint)
	end

	stdscr:refresh()

	-- Refresh to show the iteration time + our last checkpoint
	stdscr:refresh()
end
