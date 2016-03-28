sudo apt-get update
sudo apt-get -y install git
sudo apt-get -y install make
sudo apt-get -y install g++
sudo apt-get -y install libtool
sudo apt-get -y install pkg-config
sudo apt-get -y install build-essential
sudo apt-get -y install autoconf
sudo apt-get -y install automake
sudo apt-get -y install uuid-dev
sudo apt-get -y install luarocks

echo "Installing zeromq..."
wget http://download.zeromq.org/zeromq-2.2.0.tar.gz
tar -xzf zeromq-2.2.0.tar.gz
rm zeromq-2.2.0.tar.gz
cd zeromq-2.2.0
./configure
make
sudo make install
sudo ldconfig
cd ..

git clone https://github.com/Bindernews/HappyQuickNes.git
cd HappyQuickNes

echo "Installing LuaJIT..."
wget http://luajit.org/download/LuaJIT-2.0.4.tar.gz
tar -xzf LuaJIT-2.0.4.tar.gz
mv LuaJIT-2.0.4 LuaJIT
rm LuaJIT-2.0.4.tar.gz
cd LuaJIT
sudo make install
cd ../linux
echo "Installing HappyQuickNes..."
make
cd ../..

cp HappyQuickNes/hqnes hqnclient

echo "Installing lua dependencies..."
sudo luarocks install luasocket
sudo luarocks install lua-zmq
sudo ldconfig

echo "Setting up init"
sudo cp startEmus.conf /etc/init/

echo "Rebooting"
sudo reboot
