
#include <iostream>
#include <fstream>
// #include <json.hpp>
#include "hqn.h"
#include "hqn_lua.h"

#ifndef CONFIG_FILENAME
#define CONFIG_FILENAME "config.json"
#endif

#define DEFAULT_FILENAME "hqn"

// Import json so we can read the config file.
// using json = nlohmann::json;

namespace hqn
{

// Print the usage message.
void printUsage(const char *filename)
{
    const char *fname = filename ? filename : DEFAULT_FILENAME;
    std::cout << "usage: " << fname << " <romfile> <lua_script>" << std::endl;
}


int hqn_main(int argc, char **argv)
{
    // We take two arguments, the rom file and a lua script to run.
    if (argc < 3)
    {
        printUsage(argv[0]);
        return 1;
    }

    // But before we do that load the config file
    // std::ifstream cfgFile (CONFIG_FILENAME);
    // if (!cfgFile.is_open())
    // {
    //     std::cerr << "Cannot open " CONFIG_FILENAME ". Aborting." << std::endl;
    //     return 1;
    // }
    // json cfg;
    // cfgFile >> cfg;
    // cfgFile.close();

    // Now we read our config file
    // TODO read config file

    // Now we create our emulator state, allocated on the heap just because
    HQNState *hstate = new HQNState();

    // And set up our lua state
    lua_State *lstate = luaL_newstate();
    luaL_openlibs(lstate);
    hqn_lua::init_nes(lstate, hstate);

    blargg_err_t err;

    // Now load the ROM

    err = hstate->loadROM(argv[1]);
    if (err)
    {
        std::cerr << "Failed to load rom " << argv[1] << ": "
                  << err << std::endl;
        return 1;
    }

    // Now run the Lua script.
    int luaErr = luaL_dofile(lstate, argv[2]);
	if (luaErr != 0)
	{
		std::cerr << "Lua error: " << lua_tostring(lstate, -1) << std::endl;
	}

    // Always delete for good measure
    lua_close(lstate);
    delete hstate;

    return 0;
}

} // end namespace hqn


// Should be the entry point
int main(int argc, char *argv[])
{
    return hqn::hqn_main(argc, argv);
}
