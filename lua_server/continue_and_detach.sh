echo "Yipppyyyyyy! It's a me, MarI/O!"
echo "Killing any process using port 56506..."
fuser -k 56506/tcp
echo "Killing any screens named mario..."
screen -X -S mario kill
echo "Continuing from where we left of..."
screen -d -m -S mario lua server.lua backup.checkpoint
