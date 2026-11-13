#include "tuner/note.hpp"

#include <cmath>

namespace tuner {

float cents(float hz, float targetHz) noexcept { return 1200.0f * std::log2(hz / targetHz); }

float midiToHz(int midi, float a4Hz) noexcept {
    return a4Hz * std::exp2(static_cast<float>(midi - 69) / 12.0f);
}

int hzToNearestMidi(float hz, float a4Hz) noexcept {
    return static_cast<int>(std::lround(69.0f + 12.0f * std::log2(hz / a4Hz)));
}

} // namespace tuner
