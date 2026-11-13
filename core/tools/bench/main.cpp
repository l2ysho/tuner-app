#include "support/synth.hpp"
#include "tuner/detector.hpp"
#include "tuner/note.hpp"
#include "wav.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <string>
#include <vector>

namespace {

void usage() {
    std::fprintf(stderr,
                 "usage: tuner_bench [options] <input>...\n"
                 "  input:  path to a .wav file, or synth:<sine|saw|missing|pluck|white|pink>:"
                 "<hz>:<seconds>\n"
                 "options:\n"
                 "  --hop <samples>     analysis hop (default 512)\n"
                 "  --target <hz>       report cents against this pitch instead of the nearest "
                 "note\n"
                 "  --gate <dBFS>       noise gate (default -50)\n"
                 "  --sr <hz>           sample rate for synth inputs (default 48000)\n"
                 "CSV goes to stdout; timing goes to stderr.\n");
}

bench::Audio synthesize(const std::string &spec, float sampleRate) {
    // synth:<kind>:<hz>:<seconds>
    const auto a = spec.find(':', 6);
    const auto b = spec.find(':', a + 1);
    if (a == std::string::npos || b == std::string::npos) {
        throw std::runtime_error("bad synth spec: " + spec);
    }
    const std::string kind = spec.substr(6, a - 6);
    const double hz = std::stod(spec.substr(a + 1, b - a - 1));
    const auto n = static_cast<std::size_t>(std::stod(spec.substr(b + 1)) * sampleRate);
    using namespace tuner::synth;
    Signal s;
    if (kind == "sine") {
        s = sine(hz, sampleRate, n);
    } else if (kind == "saw") {
        s = saw(hz, sampleRate, n);
    } else if (kind == "missing") {
        s = missingFundamental(hz, sampleRate, n);
    } else if (kind == "pluck") {
        s = pluck(hz, sampleRate, n, static_cast<std::size_t>(0.1 * sampleRate));
    } else if (kind == "white") {
        s = whiteNoise(n, 1);
    } else if (kind == "pink") {
        s = pinkNoise(n, 1);
    } else {
        throw std::runtime_error("unknown synth kind: " + kind);
    }
    scaleToDb(s, -20.0);
    return {std::move(s), sampleRate};
}

float centsFor(const tuner::PitchResult &r, float target) {
    if (!r.voiced) {
        return 0.0f;
    }
    const float ref = target > 0.0f ? target : tuner::midiToHz(tuner::hzToNearestMidi(r.hz));
    return tuner::cents(r.hz, ref);
}

} // namespace

int main(int argc, char **argv) {
    std::size_t hop = 512;
    float target = 0.0f;
    float gate = -50.0f;
    float synthRate = 48000.0f;
    std::vector<std::string> inputs;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) {
                usage();
                std::exit(2);
            }
            return argv[++i];
        };
        if (arg == "--hop") {
            hop = std::stoul(next());
        } else if (arg == "--target") {
            target = std::stof(next());
        } else if (arg == "--gate") {
            gate = std::stof(next());
        } else if (arg == "--sr") {
            synthRate = std::stof(next());
        } else if (arg == "-h" || arg == "--help") {
            usage();
            return 0;
        } else {
            inputs.push_back(arg);
        }
    }
    if (inputs.empty() || hop == 0) {
        usage();
        return 2;
    }

    std::printf("input,time,mpm_hz,mpm_cents,mpm_clarity,mpm_voiced,"
                "yin_hz,yin_cents,yin_clarity,yin_voiced\n");
    try {
        for (const auto &input : inputs) {
            const bench::Audio audio = input.rfind("synth:", 0) == 0 ? synthesize(input, synthRate)
                                                                     : bench::readWav(input);
            tuner::DetectorConfig cfg;
            cfg.sampleRate = audio.sampleRate;
            cfg.gateDb = gate;
            tuner::PitchDetector mpm(cfg);
            tuner::YinDetector yin(cfg);
            const auto window = static_cast<std::size_t>(cfg.window);

            using Clock = std::chrono::steady_clock;
            Clock::duration mpmTime{}, yinTime{};
            std::size_t frames = 0;
            for (std::size_t end = window; end <= audio.samples.size(); end += hop, ++frames) {
                const float *frame = audio.samples.data() + end - window;
                const auto t0 = Clock::now();
                const auto m = mpm.process(frame, window);
                const auto t1 = Clock::now();
                const auto y = yin.process(frame, window);
                const auto t2 = Clock::now();
                mpmTime += t1 - t0;
                yinTime += t2 - t1;
                std::printf("%s,%.4f,%.3f,%.2f,%.3f,%d,%.3f,%.2f,%.3f,%d\n", input.c_str(),
                            static_cast<double>(end) / audio.sampleRate, m.hz, centsFor(m, target),
                            m.clarity, m.voiced ? 1 : 0, y.hz, centsFor(y, target), y.clarity,
                            y.voiced ? 1 : 0);
            }
            if (frames > 0) {
                using us = std::chrono::duration<double, std::micro>;
                std::fprintf(stderr, "%s: %zu frames, mpm %.1f us/frame, yin %.1f us/frame\n",
                             input.c_str(), frames, us(mpmTime).count() / frames,
                             us(yinTime).count() / frames);
            }
        }
    } catch (const std::exception &e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
    return 0;
}
