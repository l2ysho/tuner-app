#pragma once

namespace tuner {

inline constexpr float kDefaultA4Hz = 440.0f;

float cents(float hz, float targetHz) noexcept;
float midiToHz(int midi, float a4Hz = kDefaultA4Hz) noexcept;
int hzToNearestMidi(float hz, float a4Hz = kDefaultA4Hz) noexcept;

} // namespace tuner
