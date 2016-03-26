#!/bin/bash
while [ 1 ]; do
	sleep 300
	sudo kill -9 `pgrep hqnes`
done
