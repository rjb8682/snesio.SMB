#ifndef __HQN_LUA_H__
#define __HQN_LUA_H__

#include <lua.hpp>
#include "hqn.h"

namespace hqn_lua
{

// Basically import HQNState into this namespace as well
using HQNState = hqn::HQNState;

/*
Given the lua_State get the corresponding HQNState
*/
HQNState *hqn_get_state(lua_State *L);

/*
Get the NES emulator from the Lua state.
Used by the lua C api.
*/
Nes_Emu *hqn_get_nes(lua_State *L);

/*
Initialize the lua state with functions for working with the NES
This should be the first function you call.
*/
void init_nes(lua_State *L, HQNState *state);

/* Compare ascii strings in a case-insensitive manner. */
int stricmp(char const *a, char const *b);

/* Macro for lua calls which are not yet implemented. */
#define HQN_UNIMPLEMENTED(L) luaL_error(L, "NOT YET IMPLEMENTED")

/* Macro for getting the HQNState */
#define HQN_STATE(var) HQNState *var = hqn_get_state(L)
/* Macro for getting the Nes_Emu */
#define HQN_EMULATOR(var) Nes_Emu *var = hqn_get_nes(L)

}
#endif // __HQN_LUA_H__