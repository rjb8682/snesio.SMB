print("frames,fitness")
for line in open("filenames"):
    line = line.split()
    if len(line) > 8:
        filename = line[8].split("_")
        if len(filename) > 1:
            fitness = filename[0]
            frames = filename[1].split(".genome")[0]
            print(frames + "," + fitness)
