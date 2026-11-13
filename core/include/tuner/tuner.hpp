#pragma once

#include "tuner/detector.hpp"
#include "tuner/note.hpp"

#include <array>
#include <cstddef>
#include <span>

namespace tuner {

struct TunerConfig {
    float a4Hz = kDefaultA4Hz;
    float toleranceCents = 3.0f;
    double lockHoldSec = 0.2;
    double idleAfterSec = 1.0;
    float emaAlpha = 0.35f;
};

struct TunerState {
    int midi = -1;
    int stringIndex = -1; // -1 in chromatic mode
    float hz = 0.0f;
    float cents = 0.0f;
    bool voiced = false;
    bool locked = false;
    bool idle = true;
};

// Smoothing, string matching and lock detection. push() does not allocate.
class Tuner {
  public:
    static constexpr std::size_t kMaxStrings = 12;
    static constexpr std::size_t kMedianSize = 5;

    explicit Tuner(const TunerConfig &config = {});

    // Empty tuning = chromatic mode. Extra strings beyond kMaxStrings are ignored.
    void setTuning(std::span<const float> stringHz) noexcept;
    void setReference(float a4Hz) noexcept;
    void setTolerance(float cents) noexcept;
    // -1 = auto string detection.
    void setManualString(int index) noexcept;
    void reset() noexcept;

    TunerState push(const PitchResult &reading, double timestampSec) noexcept;
    const TunerState &state() const noexcept { return state_; }

  private:
    struct Target {
        int midi;
        int stringIndex;
        float hz;
    };
    float foldOctave(float hz) const noexcept;
    Target targetFor(float hz) const noexcept;
    void clearSmoothing() noexcept;

    TunerConfig cfg_;
    std::array<float, kMaxStrings> strings_{};
    std::size_t stringCount_ = 0;
    int manualString_ = -1;

    std::array<float, kMedianSize> history_{}; // log2(hz)
    std::size_t historyCount_ = 0;
    std::size_t historyNext_ = 0;
    float ema_ = 0.0f;
    bool emaValid_ = false;
    int currentTargetMidi_ = -1;
    int currentString_ = -1;
    double lastVoicedSec_ = -1.0;
    double inToleranceSinceSec_ = -1.0;
    TunerState state_;
};

} // namespace tuner
