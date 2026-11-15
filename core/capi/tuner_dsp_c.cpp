#include "tuner_dsp_c.h"

#include "tuner/detector.hpp"
#include "tuner/tuner.hpp"

#include <new>
#include <variant>

struct tdsp_detector {
    std::variant<tuner::PitchDetector, tuner::YinDetector> impl;
};

struct tdsp_tuner {
    tuner::Tuner impl;
};

namespace {

tuner::DetectorConfig toCpp(const tdsp_detector_config &c) {
    tuner::DetectorConfig out;
    out.sampleRate = c.sample_rate;
    out.window = c.window;
    out.minHz = c.min_hz;
    out.maxHz = c.max_hz;
    out.clarityThreshold = c.clarity_threshold;
    out.gateDb = c.gate_db;
    return out;
}

tuner::TunerConfig toCpp(const tdsp_tuner_config &c) {
    tuner::TunerConfig out;
    out.a4Hz = c.a4_hz;
    out.toleranceCents = c.tolerance_cents;
    out.releaseMarginCents = c.release_margin_cents;
    out.lockHoldSec = c.lock_hold_sec;
    out.idleAfterSec = c.idle_after_sec;
    out.emaSlowAlpha = c.ema_slow_alpha;
    out.emaFastAlpha = c.ema_fast_alpha;
    out.emaFastCents = c.ema_fast_cents;
    return out;
}

tdsp_pitch toC(const tuner::PitchResult &r) { return {r.hz, r.clarity, r.rmsDb, r.voiced}; }

tuner::PitchResult toCpp(const tdsp_pitch &p) {
    tuner::PitchResult r;
    r.hz = p.hz;
    r.clarity = p.clarity;
    r.rmsDb = p.rms_db;
    r.voiced = p.voiced;
    return r;
}

} // namespace

extern "C" {

tdsp_detector_config tdsp_detector_config_default(void) {
    const tuner::DetectorConfig d;
    return {d.sampleRate, d.window, d.minHz, d.maxHz, d.clarityThreshold, d.gateDb};
}

tdsp_detector *tdsp_detector_create(tdsp_algorithm algorithm, const tdsp_detector_config *config) {
    const tuner::DetectorConfig cfg = config ? toCpp(*config) : tuner::DetectorConfig{};
    // The C ABI must not let bad_alloc escape into Swift or JNI.
    try {
        if (algorithm == TDSP_ALGORITHM_YIN) {
            return new tdsp_detector{tuner::YinDetector(cfg)};
        }
        return new tdsp_detector{tuner::PitchDetector(cfg)};
    } catch (const std::bad_alloc &) {
        return nullptr;
    }
}

void tdsp_detector_destroy(tdsp_detector *detector) { delete detector; }

tdsp_pitch tdsp_detector_process(tdsp_detector *detector, const float *samples, size_t count) {
    return std::visit([&](auto &d) { return toC(d.process(samples, count)); }, detector->impl);
}

tdsp_tuner_config tdsp_tuner_config_default(void) {
    const tuner::TunerConfig d;
    return {d.a4Hz,         d.toleranceCents, d.releaseMarginCents, d.lockHoldSec,
            d.idleAfterSec, d.emaSlowAlpha,   d.emaFastAlpha,       d.emaFastCents};
}

tdsp_tuner *tdsp_tuner_create(const tdsp_tuner_config *config) {
    try {
        return new tdsp_tuner{tuner::Tuner(config ? toCpp(*config) : tuner::TunerConfig{})};
    } catch (const std::bad_alloc &) {
        return nullptr;
    }
}

void tdsp_tuner_destroy(tdsp_tuner *tuner) { delete tuner; }

void tdsp_tuner_set_tuning(tdsp_tuner *tuner, const float *string_hz, size_t count) {
    tuner->impl.setTuning(string_hz, string_hz ? count : 0);
}

void tdsp_tuner_set_reference(tdsp_tuner *tuner, float a4_hz) { tuner->impl.setReference(a4_hz); }

void tdsp_tuner_set_tolerance(tdsp_tuner *tuner, float cents) { tuner->impl.setTolerance(cents); }

void tdsp_tuner_set_manual_string(tdsp_tuner *tuner, int index) {
    tuner->impl.setManualString(index);
}

void tdsp_tuner_reset(tdsp_tuner *tuner) { tuner->impl.reset(); }

tdsp_tuner_state tdsp_tuner_push(tdsp_tuner *tuner, tdsp_pitch pitch, double timestamp_sec) {
    const tuner::TunerState s = tuner->impl.push(toCpp(pitch), timestamp_sec);
    return {s.midi, s.stringIndex, s.hz, s.cents, s.voiced, s.locked, s.idle};
}

} // extern "C"
