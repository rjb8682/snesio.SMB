
#include "hqn.h"
#include <sys/stat.h>
#include <cstdio>

#define READ_SIZE (1024 * 1024)

namespace hqn
{

// simulate the write so we'll know how long the buffer needs to be
class Sim_Writer : public Data_Writer
{
	long size_;
public:
	Sim_Writer() :size_(0) { }
	error_t write(const void *, long size)
	{
		size_ += size;
		return 0;
	}
	long size() const { return size_; }
};


size_t getFileSize(const char *filename)
{
    struct stat s;
    if (stat(filename, &s) == 0)
    {
        return s.st_size;
    }
    else
    {
        return 0;
    }
}

// Constructor
HQNState::HQNState()
{
    m_emu = new Nes_Emu();
    joypad[0] = 0x00;
    joypad[1] = 0x00;

    m_romData = nullptr;
    m_romSize = 0;

	m_emu->set_tracecb(nullptr);
}

// Destructor
HQNState::~HQNState()
{
    delete m_emu;
}

const char *HQNState::setSampleRate(int rate)
{
	const char *ret = m_emu->set_sample_rate(rate);
	if (!ret)
		m_emu->set_equalizer(Nes_Emu::nes_eq);
	return ret;
}

// Load a ROM image
const char *HQNState::loadROM(const char *filename)
{
    // unload any existing rom data
    unloadRom();
    // Load the file into memory
    size_t dataSize = getFileSize(filename);

    if (dataSize == 0)
    { return "Failed to open file"; }

    uint8_t *data = new uint8_t[dataSize];
    uint8_t *dataInsert = data;
    size_t readAmount = 0; // how many bytes we read

    FILE *fd = fopen(filename, "rb");
    if (!fd)
    {
        delete[] data;
        return "Failed to open file";
    }

    do
    {
        readAmount = fread(dataInsert, 1, dataSize - (dataInsert - data), fd);
        dataInsert += readAmount;
	} while (readAmount != 0);

    m_romData = data;
    m_romSize = dataSize;


    // Now finally load the rom. Ugh
    Mem_File_Reader r(data, (int)dataSize);
    Auto_File_Reader a(r);
    return m_emu->load_ines(a);
}

void HQNState::unloadRom()
{
    if (m_romData)
    {
        delete[] m_romData;
        m_romData = nullptr;
        m_romSize = 0;
    }
}

// Advance the emulator
const char *HQNState::advanceFrame()
{
    return m_emu->emulate_frame(joypad[0], joypad[1]);
}
    
} // end namespace hqn
