
#include "hqn_lua.h"
#include <cctype>

#define HQN_STATE_REF "_hqn_state"

namespace hqn_lua
{
	/* Delcarations for all the init functions. */
	int emu_init(lua_State *L);
	int joypad_init(lua_State *L);
	int mainmemory_init(lua_State *L);

void init_nes(lua_State *L, HQNState *state)
{
    lua_pushlightuserdata(L, state);
    lua_setfield(L, LUA_GLOBALSINDEX, HQN_STATE_REF);

	emu_init(L);
	joypad_init(L);
	mainmemory_init(L);
}

int stricmp(char const *a, char const *b)
{
	for (;; a++, b++) {
		int d = tolower(*a) - tolower(*b);
		if (d != 0 || !*a)
			return d;
	}
}

Nes_Emu *hqn_get_nes(lua_State *L)
{
    return hqn_get_state(L)->emu();
}

HQNState *hqn_get_state(lua_State *L)
{
    lua_getfield(L, LUA_GLOBALSINDEX, HQN_STATE_REF);
    HQNState *ref = (HQNState*)lua_touserdata(L, -1);
    lua_pop(L, 1);
    return ref;
}

}
