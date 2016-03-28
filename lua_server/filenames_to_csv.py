import sys
exp_name = sys.argv[1]

params = exp_name.split("_")
header = ""
extras = []
if len(params) > 7:
    extras = params[1:7]
    header = "experiment,population,stale_species,add_link,add_node,step_size,"

lines = []
print(header + "frames,fitness")
seenFitnesses = set()
for line in open("filenames"):
    line = line.split()
    if len(line) > 8:
        filename = line[8].split("_")
        if len(filename) > 1:
            fitness = filename[0]
            if fitness in seenFitnesses:
                continue
            seenFitnesses.add(fitness)
            
            fitness = float(fitness)
            frames = int(filename[1].split(".genome")[0])
            lines.append([frames, fitness])

for line in sorted(lines, key=lambda x: x[0]):
    extra = ",".join(extras)
    if extra != "":
        extra += ","
    print(extra + str(line[0]) + "," + str(line[1]))
