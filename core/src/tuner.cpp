#include "tuner/tuner.hpp"

#include <algorithm>
#include <cmath>

namespace tuner {

namespace {
constexpr float kOctaveGuardCents = 100.0f;
constexpr float kOctaveFoldCents = 45.0f;
constexpr float kSubOctaveGuardCents = 600.0f;
} // namespace

Tuner::Tuner(const TunerConfig &config) : cfg_(config) {}

void Tuner::setTuning(std::span<const float> stringHz) noexcept {
    stringCount_ = std::min(stringHz.size(), kMaxStrings);
    std::copy_n(stringHz.begin(), stringCount_, strings_.begin());
    if (manualString_ >= static_cast<int>(stringCount_)) {
        manualString_ = -1;
    }
    clearSmoothing();
}

void Tuner::setReference(float a4Hz) noexcept {
    cfg_.a4Hz = a4Hz;
    clearSmoothing();
}

void Tuner::setTolerance(float cents) noexcept { cfg_.toleranceCents = cents; }

void Tuner::setManualString(int index) noexcept {
    manualString_ = index >= 0 && index < static_cast<int>(stringCount_) ? index : -1;
    clearSmoothing();
}

void Tuner::reset() noexcept {
    clearSmoothing();
    lastVoicedSec_ = -1.0;
    state_ = {};
}

void Tuner::clearSmoothing() noexcept {
    historyCount_ = 0;
    historyNext_ = 0;
    emaValid_ = false;
    currentTargetMidi_ = -1;
    currentString_ = -1;
    inToleranceSinceSec_ = -1.0;
}

float Tuner::foldOctave(float hz) const noexcept {
    if (stringCount_ == 0) {
        return hz;
    }
    auto distance = [&](float f) {
        if (manualString_ >= 0) {
            return std::abs(cents(f, strings_[static_cast<std::size_t>(manualString_)]));
        }
        float best = 1e9f;
        for (std::size_t i = 0; i < stringCount_; ++i) {
            best = std::min(best, std::abs(cents(f, strings_[i])));
        }
        return best;
    };
    if (distance(hz) <= kOctaveGuardCents) {
        return hz;
    }
    // An octave error keeps the pitch class, so the folded reading must clearly be the string's
    // note. At +-50 c the class is ambiguous and a badly detuned neighbour string is likelier.
    auto isOctaveError = [&](float f) { return distance(f) <= kOctaveFoldCents; };
    // Down first: detectors err an octave high far more often than low.
    if (isOctaveError(hz * 0.5f)) {
        return hz * 0.5f;
    }
    // Sub-octave errors are rare, so only trust one when the reading sits far below every
    // candidate string; otherwise a slack low string would be folded onto a higher one.
    float lowest = strings_[manualString_ >= 0 ? static_cast<std::size_t>(manualString_) : 0];
    if (manualString_ < 0) {
        for (std::size_t i = 1; i < stringCount_; ++i) {
            lowest = std::min(lowest, strings_[i]);
        }
    }
    if (cents(hz, lowest) < -kSubOctaveGuardCents && isOctaveError(hz * 2.0f)) {
        return hz * 2.0f;
    }
    return hz;
}

Tuner::Target Tuner::targetFor(float hz) const noexcept {
    if (stringCount_ == 0) {
        const int midi = hzToNearestMidi(hz, cfg_.a4Hz);
        return {midi, -1, midiToHz(midi, cfg_.a4Hz)};
    }
    std::size_t index = 0;
    if (manualString_ >= 0) {
        index = static_cast<std::size_t>(manualString_);
    } else {
        for (std::size_t i = 1; i < stringCount_; ++i) {
            if (std::abs(cents(hz, strings_[i])) < std::abs(cents(hz, strings_[index]))) {
                index = i;
            }
        }
    }
    const float stringHz = strings_[index];
    return {hzToNearestMidi(stringHz, cfg_.a4Hz), static_cast<int>(index), stringHz};
}

TunerState Tuner::push(const PitchResult &reading, double timestampSec) noexcept {
    if (!reading.voiced || reading.hz <= 0.0f) {
        state_.voiced = false;
        state_.locked = false;
        inToleranceSinceSec_ = -1.0;
        if (!state_.idle && timestampSec - lastVoicedSec_ > cfg_.idleAfterSec) {
            clearSmoothing();
            state_ = {};
        }
        return state_;
    }
    lastVoicedSec_ = timestampSec;

    const float hz = foldOctave(reading.hz);
    history_[historyNext_] = std::log2(hz);
    historyNext_ = (historyNext_ + 1) % kMedianSize;
    historyCount_ = std::min(historyCount_ + 1, kMedianSize);
    std::array<float, kMedianSize> sorted{};
    std::copy_n(history_.begin(), historyCount_, sorted.begin());
    std::sort(sorted.begin(), sorted.begin() + static_cast<std::ptrdiff_t>(historyCount_));
    const float medianHz = std::exp2(sorted[historyCount_ / 2]);

    // Target follows the median so a single outlier (e.g. a strong harmonic) cannot switch it.
    const Target target = targetFor(medianHz);
    bool wasLocked = state_.locked;
    if (target.midi != currentTargetMidi_ || target.stringIndex != currentString_) {
        emaValid_ = false;
        inToleranceSinceSec_ = -1.0;
        wasLocked = false;
        currentTargetMidi_ = target.midi;
        currentString_ = target.stringIndex;
    }

    const float rawCents = cents(medianHz, target.hz);
    ema_ = emaValid_ ? ema_ + cfg_.emaAlpha * (rawCents - ema_) : rawCents;
    emaValid_ = true;

    const float window = cfg_.toleranceCents + (wasLocked ? cfg_.releaseMarginCents : 0.0f);
    const bool inTolerance = std::abs(ema_) <= window;
    if (!inTolerance) {
        inToleranceSinceSec_ = -1.0;
    } else if (inToleranceSinceSec_ < 0.0) {
        inToleranceSinceSec_ = timestampSec;
    }

    state_.midi = target.midi;
    state_.stringIndex = target.stringIndex;
    state_.hz = medianHz;
    state_.cents = ema_;
    state_.voiced = true;
    state_.idle = false;
    state_.locked =
        wasLocked ? inTolerance
                  : inTolerance && timestampSec - inToleranceSinceSec_ >= cfg_.lockHoldSec - 1e-9;
    return state_;
}

} // namespace tuner
