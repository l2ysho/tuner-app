#include "tuner/note.hpp"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

using Catch::Approx;

TEST_CASE("cents is zero at the target and ±100 one semitone away") {
    CHECK(tuner::cents(440.0f, 440.0f) == Approx(0.0f).margin(1e-4));
    CHECK(tuner::cents(tuner::midiToHz(70), 440.0f) == Approx(100.0f).margin(1e-2));
    CHECK(tuner::cents(tuner::midiToHz(68), 440.0f) == Approx(-100.0f).margin(1e-2));
}

TEST_CASE("midiToHz matches standard guitar strings") {
    CHECK(tuner::midiToHz(40) == Approx(82.4069f).margin(1e-3)); // E2
    CHECK(tuner::midiToHz(35) == Approx(61.7354f).margin(1e-3)); // B1
    CHECK(tuner::midiToHz(64) == Approx(329.628f).margin(1e-2)); // E4
}

TEST_CASE("reference pitch shifts every note") {
    CHECK(tuner::midiToHz(69, 432.0f) == Approx(432.0f));
    CHECK(tuner::hzToNearestMidi(432.0f, 432.0f) == 69);
}

TEST_CASE("hzToNearestMidi rounds to the closest semitone") {
    CHECK(tuner::hzToNearestMidi(82.4f) == 40);
    CHECK(tuner::hzToNearestMidi(84.0f) == 40);
    CHECK(tuner::hzToNearestMidi(85.5f) == 41);
}
