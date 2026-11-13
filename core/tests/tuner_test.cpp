#include "support/synth.hpp"
#include "tuner/detector.hpp"
#include "tuner/tuner.hpp"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/generators/catch_generators.hpp>

#include <array>
#include <cmath>

using namespace tuner;
using Catch::Approx;

namespace {

constexpr std::array<float, 6> kStandard = {82.4069f, 110.0f,   146.832f,
                                            195.998f, 246.942f, 329.628f};
constexpr double kHopSec = 0.01;

PitchResult voiced(float hz) { return {hz, 0.99f, -20.0f, true}; }
PitchResult unvoiced() { return {0.0f, 0.1f, -70.0f, false}; }

float detuned(float hz, float cents) { return hz * std::exp2(cents / 1200.0f); }

} // namespace

TEST_CASE("starts idle and becomes active on a voiced reading") {
    Tuner t;
    CHECK(t.state().idle);
    const auto s = t.push(voiced(440.0f), 0.0);
    CHECK_FALSE(s.idle);
    CHECK(s.voiced);
    CHECK(s.midi == 69);
    CHECK(s.stringIndex == -1);
    CHECK(s.cents == Approx(0.0f).margin(1e-3));
}

TEST_CASE("chromatic mode follows the reference pitch") {
    Tuner t;
    t.setReference(432.0f);
    const auto s = t.push(voiced(440.0f), 0.0);
    CHECK(s.midi == 69);
    CHECK(s.cents == Approx(cents(440.0f, 432.0f)).margin(1e-2));
}

TEST_CASE("auto string mode picks the nearest string") {
    Tuner t;
    t.setTuning(kStandard);
    CHECK(t.push(voiced(detuned(110.0f, -30.0f)), 0.0).stringIndex == 1);
    t.reset();
    const auto s = t.push(voiced(detuned(329.628f, 20.0f)), 0.0);
    CHECK(s.stringIndex == 5);
    CHECK(s.midi == 64);
    CHECK(s.cents == Approx(20.0f).margin(0.05));
}

TEST_CASE("manual string overrides auto detection") {
    Tuner t;
    t.setTuning(kStandard);
    t.setManualString(0);
    const auto s = t.push(voiced(90.0f), 0.0);
    CHECK(s.stringIndex == 0);
    CHECK(s.cents == Approx(cents(90.0f, 82.4069f)).margin(0.05));
}

TEST_CASE("octave guard folds octave errors onto a string") {
    Tuner t;
    t.setTuning(kStandard);
    const float wrong = GENERATE(2.0f * 82.4069f * 1.004f, 0.5f * 82.4069f * 1.004f);
    // E3 and E1 are not strings of standard tuning: both must fold onto E2.
    const auto s = t.push(voiced(wrong), 0.0);
    INFO("hz=" << wrong);
    CHECK(s.stringIndex == 0);
    CHECK(s.cents == Approx(cents(1.004f, 1.0f)).margin(0.05));
}

TEST_CASE("octave guard keeps readings that already match a string") {
    Tuner t;
    t.setTuning(kStandard);
    // E4 (high E string) is exactly two octaves above E2 and must stay E4.
    const auto s = t.push(voiced(329.628f), 0.0);
    CHECK(s.stringIndex == 5);
}

TEST_CASE("median rejects a single outlier") {
    Tuner t;
    double now = 0.0;
    for (int i = 0; i < 5; ++i, now += kHopSec) {
        t.push(voiced(440.0f), now);
    }
    const auto s = t.push(voiced(detuned(440.0f, 40.0f)), now);
    CHECK(std::abs(s.cents) < 0.5f);
}

TEST_CASE("lock needs the tolerance held for 200 ms") {
    Tuner t;
    double now = 0.0;
    TunerState s;
    for (; now < 0.19; now += kHopSec) {
        s = t.push(voiced(detuned(440.0f, 1.0f)), now);
        CHECK_FALSE(s.locked);
    }
    for (; now < 0.25; now += kHopSec) {
        s = t.push(voiced(detuned(440.0f, 1.0f)), now);
    }
    CHECK(s.locked);

    SECTION("leaving the tolerance releases the lock") {
        for (int i = 0; i < 10; ++i, now += kHopSec) {
            s = t.push(voiced(detuned(440.0f, 8.0f)), now);
        }
        CHECK_FALSE(s.locked);
    }
}

TEST_CASE("tolerance setting controls the lock") {
    Tuner t;
    t.setTolerance(1.0f);
    TunerState s;
    for (double now = 0.0; now < 0.5; now += kHopSec) {
        s = t.push(voiced(detuned(440.0f, 2.0f)), now);
    }
    CHECK_FALSE(s.locked);
}

TEST_CASE("goes idle after one second without a voiced reading") {
    Tuner t;
    t.push(voiced(440.0f), 0.0);
    auto s = t.push(unvoiced(), 0.5);
    CHECK_FALSE(s.voiced);
    CHECK_FALSE(s.idle);
    CHECK(s.midi == 69);
    s = t.push(unvoiced(), 1.01);
    CHECK(s.idle);
    CHECK(s.midi == -1);
}

TEST_CASE("pluck reaches a stable reading within 150 ms") {
    const double sampleRate = 48000.0;
    const std::size_t hop = 512;
    const std::size_t window = 4096;
    const double onsetSec = 0.2;
    const int stringIdx = GENERATE(0, 2, 5);
    const float target = kStandard[static_cast<std::size_t>(stringIdx)];
    const float trueHz = detuned(target, 7.0f);

    auto signal = synth::pluck(trueHz, sampleRate, static_cast<std::size_t>(sampleRate * 1.0),
                               static_cast<std::size_t>(onsetSec * sampleRate));
    synth::scaleToDb(signal, -20.0);

    PitchDetector detector;
    Tuner t;
    t.setTuning(kStandard);
    double stableSince = -1.0;
    for (std::size_t end = window; end <= signal.size(); end += hop) {
        const double now = static_cast<double>(end) / sampleRate;
        const auto s = t.push(detector.process(signal.data() + end - window, window), now);
        const bool good =
            s.voiced && s.stringIndex == stringIdx && std::abs(s.cents - 7.0f) <= 1.0f;
        if (!good) {
            stableSince = -1.0;
        } else if (stableSince < 0.0) {
            stableSince = now;
        }
    }
    INFO("string=" << stringIdx << " stableSince=" << stableSince);
    REQUIRE(stableSince > 0.0);
    CHECK(stableSince - onsetSec <= 0.150);
}
