echo "Spawning $1 processes"
for ((i = 1; i <= $1; i++)) 
do
    ./run_loop.sh zmqclient.lua &
done
