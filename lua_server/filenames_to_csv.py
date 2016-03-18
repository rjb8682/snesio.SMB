lines = []
print("frames,fitness")
for line in open("filenames"):
    line = line.split()
    if len(line) > 8:
        filename = line[8].split("_")
        if len(filename) > 1:
            fitness = float(filename[0])
            frames = int(filename[1].split(".genome")[0])
            lines.append([frames, fitness])

for line in sorted(lines, key=lambda x: x[0]):
    print(str(line[0]) + "," + str(line[1]))
