import os
import sys

def main():
    if len(sys.argv) < 2:
        print("usage: python merge_csv.py dir_name")
        return

    result = []
    header = None
    path = os.getcwd() + "/" + sys.argv[1]

    for filename in os.listdir(path):
        seen_header = False
        if filename.endswith(".csv"):
            lastLine = None
            for line in open(path + filename):
               if not seen_header:
                   header = line
                   seen_header = True
               else:
                    lastLine = line
                    result.append(line) 

            lastLine = lastLine.split(",")
            lastLine[-2] = "3000000000"
            result.append(",".join(lastLine))
        else:
            continue

    print(header + "".join(result))

if __name__ == "__main__":
    main()
