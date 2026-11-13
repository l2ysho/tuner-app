#include "tuner/tuner.hpp"

#include <algorithm>
#include <cmath>

namespace tuner {

namespace {
constexpr float kOctaveGuardCents = 100.0f;
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
    const float raw = distance(hz);
    if (raw <= kOctaveGuardCents) {
        return hz;
    }
    // Down first: detectors err an octave high far more often than low.
    if (distance(hz * 0.5f) <= kOctaveGuardCents) {
        return hz * 0.5f;
    }
    if (distance(hz * 2.0f) <= kOctaveGuardCents) {
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
        if (!state_.idle && timestampSec - lastVoicedSec_ > cfg_.idleAfterSec) {
            clearSmoothing();
            state_ = {};
        }
        return state_;
    }
    lastVoicedSec_ = timestampSec;

    const float hz = foldOctave(reading.hz);
    const Target target = targetFor(hz);
    if (target.midi != currentTargetMidi_ || target.stringIndex != currentString_) {
        clearSmoothing();
        currentTargetMidi_ = target.midi;
        currentString_ = target.stringIndex;
    }

    history_[historyNext_] = std::log2(hz);
    historyNext_ = (historyNext_ + 1) % kMedianSize;
    historyCount_ = std::min(historyCount_ + 1, kMedianSize);
    std::array<float, kMedianSize> sorted{};
    std::copy_n(history_.begin(), historyCount_, sorted.begin());
    std::sort(sorted.begin(), sorted.begin() + static_cast<std::ptrdiff_t>(historyCount_));
    const float medianHz = std::exp2(sorted[historyCount_ / 2]);

    const float rawCents = cents(medianHz, target.hz);
    ema_ = emaValid_ ? ema_ + cfg_.emaAlpha * (rawCents - ema_) : rawCents;
    emaValid_ = true;

    const bool inTolerance = std::abs(ema_) <= cfg_.toleranceCents;
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
    state_.locked = inTolerance && timestampSec - inToleranceSinceSec_ >= cfg_.lockHoldSec - 1e-9;
    return state_;
}

} // namespace tuner
