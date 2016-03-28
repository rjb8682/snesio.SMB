apt-get update
apt-get -y install git
apt-get -y install make
apt-get -y install g++
apt-get -y install libtool
apt-get -y install pkg-config
apt-get -y install build-essential
apt-get -y install autoconf
apt-get -y install automake
apt-get -y install uuid-dev
apt-get -y install luarocks

echo "Installing zeromq..."
wget http://download.zeromq.org/zeromq-2.2.0.tar.gz
tar -xzf zeromq-2.2.0.tar.gz
rm zeromq-2.2.0.tar.gz
cd zeromq-2.2.0
./configure
make
make install
ldconfig
cd ..

git clone https://github.com/Bindernews/HappyQuickNes.git
cd HappyQuickNes

echo "Installing LuaJIT..."
wget http://luajit.org/download/LuaJIT-2.0.4.tar.gz
tar -xzf LuaJIT-2.0.4.tar.gz
mv LuaJIT-2.0.4 LuaJIT
rm LuaJIT-2.0.4.tar.gz
cd LuaJIT
make install
cd ../linux
echo "Installing HappyQuickNes..."
make
cd ../..

cp HappyQuickNes/hqnes hqnclient

echo "Installing lua dependencies..."
luarocks install luasocket
luarocks install lua-zmq
ldconfig

echo "Setting up init"
cp startEmus.conf /etc/init/

echo "Rebooting"
reboot
