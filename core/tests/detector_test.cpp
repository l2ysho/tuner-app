#include "support/synth.hpp"
#include "tuner/detector.hpp"
#include "tuner/note.hpp"

#include <catch2/catch_template_test_macros.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>
#include <catch2/generators/catch_generators_range.hpp>

#include <cmath>

using namespace tuner;

namespace {

constexpr std::size_t kWindow = 4096;

// B1 (7-string / drop), standard E2..E4.
constexpr int kStrings[] = {35, 40, 45, 50, 55, 59, 64};

template <typename Detector>
PitchResult detect(const synth::Signal &s, float sampleRate = 48000.0f) {
    DetectorConfig cfg;
    cfg.sampleRate = sampleRate;
    Detector d(cfg);
    return d.process(s.data(), s.size());
}

} // namespace

TEMPLATE_TEST_CASE("clean sine and saw are within 1 cent", "[detector]", PitchDetector,
                   YinDetector) {
    const float sampleRate = GENERATE(48000.0f, 44100.0f);
    const int midi = GENERATE(from_range(std::begin(kStrings), std::end(kStrings)));
    const double phase = GENERATE(0.0, 1.3);
    const bool sawWave = GENERATE(false, true);
    const double hz = midiToHz(midi);

    auto signal = sawWave ? synth::saw(hz, sampleRate, kWindow, phase)
                          : synth::sine(hz, sampleRate, kWindow, phase);
    synth::scaleToDb(signal, -20.0);
    const auto result = detect<TestType>(signal, sampleRate);

    INFO("sr=" << sampleRate << " midi=" << midi << " saw=" << sawWave << " phase=" << phase
               << " hz=" << result.hz << " clarity=" << result.clarity);
    REQUIRE(result.voiced);
    CHECK(std::abs(cents(result.hz, static_cast<float>(hz))) <= 1.0f);
}

TEMPLATE_TEST_CASE("missing fundamental has no octave error", "[detector]", PitchDetector,
                   YinDetector) {
    const int midi = GENERATE(35, 40, 45);
    const double hz = midiToHz(midi);
    auto signal = synth::missingFundamental(hz, 48000.0, kWindow, 0.7);
    synth::scaleToDb(signal, -20.0);
    const auto result = detect<TestType>(signal);

    INFO("midi=" << midi << " hz=" << result.hz);
    REQUIRE(result.voiced);
    CHECK(std::abs(cents(result.hz, static_cast<float>(hz))) <= 1.0f);
}

TEMPLATE_TEST_CASE("noise above the gate is never voiced", "[detector]", PitchDetector,
                   YinDetector) {
    const bool pink = GENERATE(false, true);
    const auto seed = GENERATE(range(1u, 21u));
    auto noise = pink ? synth::pinkNoise(kWindow, seed) : synth::whiteNoise(kWindow, seed);
    synth::scaleToDb(noise, -20.0);
    const auto result = detect<TestType>(noise);

    INFO("pink=" << pink << " seed=" << seed << " hz=" << result.hz
                 << " clarity=" << result.clarity);
    CHECK(result.rmsDb > -50.0f);
    CHECK_FALSE(result.voiced);
}

TEMPLATE_TEST_CASE("signal below the gate is unvoiced", "[detector]", PitchDetector, YinDetector) {
    auto signal = synth::saw(110.0, 48000.0, kWindow);
    synth::scaleToDb(signal, -60.0);
    const auto result = detect<TestType>(signal);
    CHECK_FALSE(result.voiced);
    CHECK(result.rmsDb < -50.0f);
}

TEMPLATE_TEST_CASE("detune sweep is monotonic without jumps", "[detector]", PitchDetector,
                   YinDetector) {
    const int midi = GENERATE(40, 64);
    const float target = midiToHz(midi);
    float previous = -1000.0f;
    for (int c = -50; c <= 50; ++c) {
        const double hz = target * std::exp2(c / 1200.0);
        auto signal = synth::saw(hz, 48000.0, kWindow);
        synth::scaleToDb(signal, -20.0);
        const auto result = detect<TestType>(signal);
        const float measured = cents(result.hz, target);

        INFO("midi=" << midi << " detune=" << c << " measured=" << measured);
        REQUIRE(result.voiced);
        if (c > -50) {
            CHECK(measured > previous);
            CHECK(measured - previous <= 2.0f);
        }
        previous = measured;
    }
}

TEST_CASE("process accepts more samples than the window", "[detector]") {
    auto signal = synth::sine(196.0, 48000.0, kWindow * 3);
    synth::scaleToDb(signal, -20.0);
    PitchDetector d;
    const auto result = d.process(signal.data(), signal.size());
    REQUIRE(result.voiced);
    CHECK(std::abs(cents(result.hz, 196.0f)) <= 1.0f);
}

TEMPLATE_TEST_CASE("bass range down to B0 with a lower minHz", "[detector]", PitchDetector,
                   YinDetector) {
    const int midi = GENERATE(23, 28, 33); // B0, E1, A1
    const double hz = midiToHz(midi);
    auto signal = synth::saw(hz, 48000.0, kWindow);
    synth::scaleToDb(signal, -20.0);
    DetectorConfig cfg;
    cfg.minHz = 28.0f;
    TestType d(cfg);
    const auto result = d.process(signal.data(), signal.size());

    INFO("midi=" << midi << " hz=" << result.hz);
    REQUIRE(result.voiced);
    CHECK(std::abs(cents(result.hz, static_cast<float>(hz))) <= 1.0f);
}
