#include "support/synth.hpp"

#include "tuner/note.hpp"
#include "tuner_dsp_c.h"

#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <catch2/generators/catch_generators_range.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>
#include <memory>

using namespace tuner;

namespace {

constexpr std::size_t kWindow = 4096;

struct DetectorDeleter {
    void operator()(tdsp_detector *d) const { tdsp_detector_destroy(d); }
};
using DetectorPtr = std::unique_ptr<tdsp_detector, DetectorDeleter>;

DetectorPtr makeDetector(tdsp_algorithm algorithm, float sampleRate, float minHz = 50.0f) {
    tdsp_detector_config cfg = tdsp_detector_config_default();
    cfg.sample_rate = sampleRate;
    cfg.min_hz = minHz;
    return DetectorPtr(tdsp_detector_create(algorithm, &cfg));
}

// Standard EADGBE, drop D's low D2, 7-string low B1.
struct Golden {
    const char *name;
    double hz;
};
constexpr Golden kGolden[] = {
    {"E2", 82.4069}, {"A2", 110.0},   {"D3", 146.832},          {"G3", 195.998},
    {"B3", 246.942}, {"E4", 329.628}, {"D2 (drop D)", 73.4162}, {"B1 (7-string)", 61.7354},
};

} // namespace

namespace {

synth::Signal stringSignal(double hz, float sampleRate, bool rich, double snrDb) {
    auto signal = rich ? synth::harmonics(hz, sampleRate, kWindow, 1, 8, 1.0, 0.7)
                       : synth::sine(hz, sampleRate, kWindow);
    synth::scaleToDb(signal, -20.0);
    if (rich) {
        auto noise = synth::whiteNoise(kWindow, 7);
        synth::scaleToDb(noise, -20.0 - snrDb);
        signal = synth::mix(signal, noise);
    }
    return signal;
}

float detectCents(tdsp_algorithm algorithm, const Golden &golden, bool rich, double snrDb) {
    const float sampleRate = 48000.0f;
    const auto signal = stringSignal(golden.hz, sampleRate, rich, snrDb);
    auto detector = makeDetector(algorithm, sampleRate);
    REQUIRE(detector);
    const tdsp_pitch p = tdsp_detector_process(detector.get(), signal.data(), signal.size());
    INFO(golden.name << " algorithm=" << algorithm << " rich=" << rich << " snr=" << snrDb
                     << " hz=" << p.hz << " clarity=" << p.clarity);
    REQUIRE(p.voiced);
    return std::abs(cents(p.hz, static_cast<float>(golden.hz)));
}

} // namespace

TEST_CASE("C API golden: sines and 40 dB SNR harmonics within 0.5 cent", "[capi][golden]") {
    const auto algorithm = GENERATE(TDSP_ALGORITHM_MPM, TDSP_ALGORITHM_YIN);
    const auto &golden = GENERATE(from_range(std::begin(kGolden), std::end(kGolden)));
    const bool rich = GENERATE(false, true);
    CHECK(detectCents(algorithm, golden, rich, 40.0) <= 0.5f);
}

// One 85 ms window at 20 dB SNR cannot reach 0.5 c; the Tuner's median and EMA smooth the rest.
TEST_CASE("C API golden: 20 dB SNR harmonics within 1.5 cent", "[capi][golden]") {
    const auto algorithm = GENERATE(TDSP_ALGORITHM_MPM, TDSP_ALGORITHM_YIN);
    const auto &golden = GENERATE(from_range(std::begin(kGolden), std::end(kGolden)));
    CHECK(detectCents(algorithm, golden, true, 20.0) <= 1.5f);
}

TEST_CASE("C API: silence and noise are not voiced", "[capi][golden]") {
    const auto algorithm = GENERATE(TDSP_ALGORITHM_MPM, TDSP_ALGORITHM_YIN);
    auto detector = makeDetector(algorithm, 48000.0f);
    REQUIRE(detector);

    const synth::Signal silence(kWindow, 0.0f);
    const tdsp_pitch quiet = tdsp_detector_process(detector.get(), silence.data(), silence.size());
    CHECK_FALSE(quiet.voiced);
    CHECK(quiet.clarity < 0.5f);

    auto noise = synth::whiteNoise(kWindow, 3);
    synth::scaleToDb(noise, -20.0);
    const tdsp_pitch hiss = tdsp_detector_process(detector.get(), noise.data(), noise.size());
    INFO("clarity=" << hiss.clarity);
    CHECK_FALSE(hiss.voiced);
}

TEST_CASE("C API: tuner reports string and cents", "[capi]") {
    tdsp_tuner *tuner = tdsp_tuner_create(nullptr);
    REQUIRE(tuner);
    const float strings[] = {82.4069f, 110.0f, 146.832f, 195.998f, 246.942f, 329.628f};
    tdsp_tuner_set_tuning(tuner, strings, 6);

    const tdsp_pitch flatA{110.0f * std::exp2(-10.0f / 1200.0f), 0.99f, -20.0f, true};
    tdsp_tuner_state s{};
    for (int i = 0; i < 5; ++i) {
        s = tdsp_tuner_push(tuner, flatA, i * 0.01);
    }
    CHECK(s.string_index == 1);
    CHECK(s.midi == 45);
    CHECK(std::abs(s.cents + 10.0f) < 0.1f);
    tdsp_tuner_destroy(tuner);
}

TEST_CASE("C API: process() stays within the per-window time budget", "[capi][timing]") {
    // Sanitizers slow the code down several times; the budget only has to catch regressions.
#if defined(__has_feature)
#if __has_feature(address_sanitizer)
    constexpr double kBudgetMs = 25.0;
#else
    constexpr double kBudgetMs = 2.0;
#endif
#else
    constexpr double kBudgetMs = 2.0;
#endif
    auto detector = makeDetector(TDSP_ALGORITHM_MPM, 48000.0f);
    REQUIRE(detector);
    auto signal = synth::saw(110.0, 48000.0, kWindow);
    synth::scaleToDb(signal, -20.0);

    // Fastest run, not the mean: a busy shared CI runner only ever adds time, a regression
    // slows every run.
    constexpr int kRuns = 50;
    tdsp_detector_process(detector.get(), signal.data(), signal.size());
    double perWindowMs = std::numeric_limits<double>::max();
    for (int i = 0; i < kRuns; ++i) {
        const auto start = std::chrono::steady_clock::now();
        tdsp_detector_process(detector.get(), signal.data(), signal.size());
        const std::chrono::duration<double, std::milli> elapsed =
            std::chrono::steady_clock::now() - start;
        perWindowMs = std::min(perWindowMs, elapsed.count());
    }
    INFO("per 4096-sample window: " << perWindowMs << " ms (budget " << kBudgetMs << " ms)");
    CHECK(perWindowMs < kBudgetMs);
}
