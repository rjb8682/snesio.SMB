#!/bin/bash
NUM_CPUS=`grep -c ^processor /proc/cpuinfo`
./runN.sh $NUM_CPUS
