#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numbers>
#include <random>
#include <vector>

namespace tuner::synth {

using Signal = std::vector<float>;

// Additive harmonics k = first..last (last = 0 → up to Nyquist) with amplitude 1/k^rolloff.
inline Signal harmonics(double hz, double sampleRate, std::size_t n, int first, int last,
                        double rolloff, double phase = 0.0) {
    Signal out(n, 0.0f);
    const int nyquistHarmonic = static_cast<int>((sampleRate / 2.0 - 1.0) / hz);
    const int top = last == 0 ? nyquistHarmonic : std::min(last, nyquistHarmonic);
    for (int k = first; k <= top; ++k) {
        const double amp = 1.0 / std::pow(static_cast<double>(k), rolloff);
        const double w = 2.0 * std::numbers::pi * hz * k / sampleRate;
        for (std::size_t i = 0; i < n; ++i) {
            out[i] += static_cast<float>(amp * std::sin(w * static_cast<double>(i) + phase * k));
        }
    }
    return out;
}

inline Signal sine(double hz, double sampleRate, std::size_t n, double phase = 0.0) {
    return harmonics(hz, sampleRate, n, 1, 1, 0.0, phase);
}

inline Signal saw(double hz, double sampleRate, std::size_t n, double phase = 0.0) {
    return harmonics(hz, sampleRate, n, 1, 0, 1.0, phase);
}

// Harmonics 2..8 at equal level: the waveform repeats at hz but has no energy at hz.
inline Signal missingFundamental(double hz, double sampleRate, std::size_t n, double phase = 0.0) {
    return harmonics(hz, sampleRate, n, 2, 8, 0.0, phase);
}

inline Signal whiteNoise(std::size_t n, std::uint32_t seed) {
    std::mt19937 rng(seed);
    std::normal_distribution<float> dist(0.0f, 1.0f);
    Signal out(n);
    for (auto &s : out) {
        s = dist(rng);
    }
    return out;
}

// Paul Kellet's economy pink filter over white noise.
inline Signal pinkNoise(std::size_t n, std::uint32_t seed) {
    Signal white = whiteNoise(n, seed);
    double b0 = 0, b1 = 0, b2 = 0;
    for (auto &s : white) {
        b0 = 0.99765 * b0 + s * 0.0990460;
        b1 = 0.96300 * b1 + s * 0.2965164;
        b2 = 0.57000 * b2 + s * 1.0526913;
        s = static_cast<float>(b0 + b1 + b2 + s * 0.1848);
    }
    return white;
}

// Plucked string: silence, then harmonics with an instant attack and per-harmonic decay.
inline Signal pluck(double hz, double sampleRate, std::size_t n, std::size_t onset,
                    double decaySec = 1.5) {
    Signal out(n, 0.0f);
    const int top = std::min(20, static_cast<int>((sampleRate / 2.0 - 1.0) / hz));
    for (int k = 1; k <= top; ++k) {
        const double amp = 1.0 / k;
        const double tau = decaySec / k;
        const double w = 2.0 * std::numbers::pi * hz * k / sampleRate;
        for (std::size_t i = onset; i < n; ++i) {
            const double t = static_cast<double>(i - onset) / sampleRate;
            out[i] += static_cast<float>(amp * std::exp(-t / tau) * std::sin(w * (i - onset)));
        }
    }
    return out;
}

inline double rmsDb(const Signal &s) {
    double sum = 0;
    for (float v : s) {
        sum += static_cast<double>(v) * v;
    }
    return 10.0 * std::log10(sum / static_cast<double>(s.size()));
}

inline Signal &scaleToDb(Signal &s, double targetDb) {
    const auto gain = static_cast<float>(std::pow(10.0, (targetDb - rmsDb(s)) / 20.0));
    for (auto &v : s) {
        v *= gain;
    }
    return s;
}

inline Signal mix(const Signal &a, const Signal &b) {
    Signal out(a);
    for (std::size_t i = 0; i < out.size() && i < b.size(); ++i) {
        out[i] += b[i];
    }
    return out;
}

} // namespace tuner::synth
