
#include "hqn_lua.h"

namespace hqn_lua
{

static const char *JOYPAD_TABLE_NAME[] = {"hqn_joypad1", "hqn_joypad2"};

static const char *JOYPAD_NAMES[] = {
    "up", "down", "left", "right", "start", "select", "b", "a"
};

static const int JOYPAD_MASKS[] = {
    16, 32, 64, 128, 8, 4, 2, 1
};

static const int JOYPAD_MAX_PAD = 8;


/// Get the index of the joypad button from its name.
int get_joypad_key_index(const char *name)
{
    for (int i = 0; i < JOYPAD_MAX_PAD; i++)
    {
        if (stricmp(name, JOYPAD_NAMES[i]) == 0)
        {
            return i;
        }
    }
    return -1;
}

int validate_joypad_id(lua_State *L, int id)
{
    int joypadID = luaL_optint(L, id, 0);
    if (joypadID > 1)
    {
        return luaL_error(L, "Invalid joypad number %d", joypadID);
    }
    return joypadID;
}

/// Get the currently pressed buttons on the joypad.
/// joypad.get([controllerID])
int joypad_get(lua_State *L)
{
    HQNState *state = hqn_get_state(L);
    int joypadID = validate_joypad_id(L, 1);

    // This is the table which will hold our return values
    int mask = state->joypad[joypadID];
    int tableIndex = lua_gettop(L);
    int insertIndex = 1; // because Lua starts from 1
    for (int i = 0; i < JOYPAD_MAX_PAD; i++)
    {
        if (mask & JOYPAD_MASKS[i])
        {
            lua_pushstring(L, JOYPAD_NAMES[i]);
            lua_rawseti(L, tableIndex, insertIndex++);
        }
    }
    return 1;
}

/// Set the currently pressed buttons
/// joypad.set(table buttons, [int controller = 0])
int joypad_set(lua_State *L)
{
    HQN_STATE(state);
    int joypadID = validate_joypad_id(L, 2);

    if (!lua_istable(L, 1))
    {
        return luaL_error(L, "Arg 1 must be a table");
    }

    int mask = state->joypad[joypadID];

    // Iterate through keys in the table and build the new joypad mask
    lua_pushnil(L);
    while (lua_next(L, 1))
    {
        // ensure we don't accidentally change the key in case it's a number
        lua_pushvalue(L, lua_gettop(L) - 2);
        const char *key = lua_tostring(L, -1);
        lua_pop(L, 1);

        int onOff = lua_toboolean(L, -1);
        int maskIndex = get_joypad_key_index(key);
        if (maskIndex != -1)
        {
            if (onOff)
            { mask |= JOYPAD_MASKS[maskIndex]; }
            else
            { mask &= ~JOYPAD_MASKS[maskIndex]; }
        }
        else
        {
            // silently ignore invalid keys
        }
        lua_pop(L, 1);
    }

    // Finally update the actual joypad state
    state->joypad[joypadID] = mask;

    // Nothing to return to Lua
    return 0;
}

int joypad_init(lua_State *L)
{
	luaL_Reg funcReg[] = {
		{ "get", &joypad_get },
		{ "set", &joypad_set },
		{ nullptr, nullptr }
	};
	luaL_register(L, "joypad", funcReg);
	return 0;
}

} // end namespace hqn_lua
