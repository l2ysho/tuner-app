// Fails if process() or push() touch the heap: both run on the audio thread.
// A separate binary because it replaces the global operator new.

#include "support/synth.hpp"
#include "tuner_dsp_c.h"

#include <cstdio>
#include <cstdlib>
#include <new>

namespace {
bool gCounting = false;
int gAllocations = 0;
} // namespace

void *operator new(std::size_t size) {
    if (gCounting) {
        ++gAllocations;
    }
    if (void *p = std::malloc(size == 0 ? 1 : size)) {
        return p;
    }
    throw std::bad_alloc();
}
void operator delete(void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }

int main() {
    using namespace tuner;
    auto signal = synth::saw(110.0, 48000.0, 4096);
    synth::scaleToDb(signal, -20.0);
    const float strings[] = {82.4069f, 110.0f, 146.832f, 195.998f, 246.942f, 329.628f};

    int failures = 0;
    for (const auto algorithm : {TDSP_ALGORITHM_MPM, TDSP_ALGORITHM_YIN}) {
        tdsp_detector *detector = tdsp_detector_create(algorithm, nullptr);
        tdsp_tuner *tuner = tdsp_tuner_create(nullptr);
        tdsp_tuner_set_tuning(tuner, strings, 6);

        gAllocations = 0;
        gCounting = true;
        for (int i = 0; i < 20; ++i) {
            const tdsp_pitch p = tdsp_detector_process(detector, signal.data(), signal.size());
            tdsp_tuner_push(tuner, p, i * 0.01);
        }
        gCounting = false;

        if (gAllocations != 0) {
            std::fprintf(stderr, "FAIL: algorithm %d allocated %d times in process()/push()\n",
                         algorithm, gAllocations);
            ++failures;
        }
        tdsp_tuner_destroy(tuner);
        tdsp_detector_destroy(detector);
    }
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
