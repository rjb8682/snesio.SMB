echo "Yipppyyyyyy! It's a me, MarI/O!"
echo "Continuing from where we left of..."

fuser -k 56507/tcp
lua server.lua backup.checkpoint
