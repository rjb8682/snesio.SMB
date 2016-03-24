#ifndef __HQN_H__
#define __HQN_H__

#include <nes_emu/Nes_Emu.h>
#include <cstdint>

namespace hqn
{

/*
State which is maintained by the emulator driver.

This should normally be obtained using hqn_get_state() if you are un a lua
function.
*/
class HQNState
{
public:
    HQNState();
    ~HQNState();

    /*
    The joypad data for the two joypads available to an NES.
    This is directly available because I'm lazy.
    */
    uint32_t joypad[2];

    /* Get the emulator this state uses. */
    inline Nes_Emu *emu() const
    { return m_emu; }

    /*
    Load a NES rom from the named file.
    Returns NULL or error string.
    */
	blargg_err_t loadROM(const char *filename);

    /*
    Advance the emulator by one frame.
    Returns NULL or error string.
    */
	blargg_err_t advanceFrame();

	blargg_err_t setSampleRate(int rate);

private:

    void unloadRom();

    /* A reference to the emulator instance. */
    Nes_Emu *m_emu;
    /* ROM file stored in memory because reasons */
    uint8_t *m_romData;
    size_t m_romSize;
};

/*
Print the usage message.
@param filename used to specify the name of the exe file, may be NULL.
*/
void printUsage(const char *filename);

} // end namespace hqn


#endif /* __HQN_H__ */