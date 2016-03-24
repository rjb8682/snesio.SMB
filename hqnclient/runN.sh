echo "Spawning $1 processes"
for i in {1..$1}
do
    echo "test"
    ( ./run_loop.sh zmqclient.lua & )
done
