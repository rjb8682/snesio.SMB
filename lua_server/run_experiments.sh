#!/bin/bash
# This script checks if an active experiment is running, runs the current experiment
# or creates a new experiment, and repeats until all experiments are complete.

echo "Checking for an active experiment..."

while true; do
    if [ -d "current" ]; then
        echo "Active experiment found. Continuing from where we left off!"
        lua dumber_server.lua current 2> err.txt
    else
        echo "No active experiment found. Setting up a new experiment."
        lua setup_server.lua
        if [ -d "current" ]; then
            echo "New experiment found. Running."
            lua dumber_server.lua current 2> err.txt
        else
            echo "No new experiments to run. Exiting."
            exit
        fi
    fi
    sleep 1
done
