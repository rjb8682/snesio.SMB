#!/bin/bash
for i in $(seq 0 31);
do
    ./csv.sh $(ls | grep "p2_e$i""_") > p2stats/e$i.csv
done


