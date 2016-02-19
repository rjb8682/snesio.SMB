echo "Yipppyyyyyy! It's a me, MarI/O!"

fuser -k 56506/tcp
lua server.lua "$@"
