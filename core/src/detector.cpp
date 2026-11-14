#include "tuner/detector.hpp"

#include <algorithm>
#include <cmath>
#include <span>

namespace tuner {

namespace detail {

std::size_t maxLagFor(const DetectorConfig &cfg) noexcept {
    const auto byPitch = static_cast<std::size_t>(std::ceil(cfg.sampleRate / cfg.minHz)) + 1;
    return std::min(byPitch, static_cast<std::size_t>(cfg.window) / 2);
}

Frame makeFrame(const DetectorConfig &cfg, const float *samples, std::size_t count) noexcept {
    const auto window = static_cast<std::size_t>(cfg.window);
    if (count > window) {
        samples += count - window;
        count = window;
    }
    double energy = 0.0;
    for (std::size_t i = 0; i < count; ++i) {
        energy += static_cast<double>(samples[i]) * samples[i];
    }
    const double meanSquare = count > 0 ? energy / static_cast<double>(count) : 0.0;
    const float rmsDb =
        meanSquare > 1e-12 ? static_cast<float>(10.0 * std::log10(meanSquare)) : -120.0f;

    const auto minLag =
        std::max<std::size_t>(2, static_cast<std::size_t>(cfg.sampleRate / cfg.maxHz));
    const auto byPitch = static_cast<std::size_t>(std::ceil(cfg.sampleRate / cfg.minHz));
    const std::size_t maxLag = count >= 4 ? std::min(byPitch, count / 2 - 1) : 0;
    return {samples, count, minLag, maxLag, rmsDb};
}

namespace {

// Vertex of the parabola through (-1, a), (0, b), (1, c): offset and value.
struct Vertex {
    double offset;
    double value;
};

Vertex parabolic(double a, double b, double c) noexcept {
    const double denom = a - 2.0 * b + c;
    if (std::abs(denom) < 1e-15) {
        return {0.0, b};
    }
    const double offset = std::clamp(0.5 * (a - c) / denom, -1.0, 1.0);
    return {offset, b - 0.25 * (a - c) * offset};
}

PitchResult finish(const DetectorConfig &cfg, const Frame &frame, double lag,
                   double clarity) noexcept {
    PitchResult out;
    out.rmsDb = frame.rmsDb;
    out.clarity = static_cast<float>(std::clamp(clarity, 0.0, 1.0));
    out.hz = lag > 0.0 ? static_cast<float>(cfg.sampleRate / lag) : 0.0f;
    out.voiced = out.clarity >= cfg.clarityThreshold && out.hz >= cfg.minHz && out.hz <= cfg.maxHz;
    if (!out.voiced) {
        out.hz = 0.0f;
    }
    return out;
}

} // namespace
} // namespace detail

PitchDetector::PitchDetector(const DetectorConfig &config)
    : cfg_(config), correlator_(static_cast<std::size_t>(config.window), detail::maxLagFor(config)),
      nsdf_(detail::maxLagFor(config) + 1) {
    keys_.resize(nsdf_.size());
}

PitchResult PitchDetector::process(const float *samples, std::size_t count) noexcept {
    const detail::Frame frame = detail::makeFrame(cfg_, samples, count);
    PitchResult silent;
    silent.rmsDb = frame.rmsDb;
    if (frame.rmsDb < cfg_.gateDb || frame.maxLag <= frame.minLag) {
        return silent;
    }

    const std::size_t lastLag = frame.maxLag + 1;
    correlator_.compute(frame.data, frame.count, frame.count, lastLag);
    const double *r = correlator_.r();
    const float *x = frame.data;

    // NSDF n(tau) = 2 r(tau) / m(tau), m(tau) = sum of squares of both overlapping parts.
    double m = 2.0 * r[0];
    nsdf_[0] = 1.0;
    for (std::size_t tau = 1; tau <= lastLag; ++tau) {
        const double head = x[tau - 1];
        const double tail = x[frame.count - tau];
        m -= head * head + tail * tail;
        nsdf_[tau] = m > 1e-12 ? 2.0 * r[tau] / m : 0.0;
    }

    // Key maxima: the highest point of each positive lobe after the zero-lag lobe.
    std::size_t keyCount = 0;
    std::size_t tau = 1;
    while (tau <= frame.maxLag && nsdf_[tau] > 0.0) {
        ++tau;
    }
    bool inLobe = false;
    std::size_t best = 0;
    for (; tau <= frame.maxLag; ++tau) {
        if (nsdf_[tau] > 0.0) {
            if (!inLobe || nsdf_[tau] > nsdf_[best]) {
                best = tau;
            }
            inLobe = true;
        } else if (inLobe) {
            inLobe = false;
            if (best >= frame.minLag) {
                keys_[keyCount++] = best;
            }
        }
    }
    if (inLobe && best >= frame.minLag && nsdf_[best + 1] < nsdf_[best]) {
        keys_[keyCount++] = best;
    }
    if (keyCount == 0) {
        return silent;
    }

    double highest = 0.0;
    const auto keys = std::span<const std::size_t>(keys_.data(), keyCount);
    for (std::size_t k : keys) {
        highest = std::max(highest, nsdf_[k]);
    }
    const double cutoff = cfg_.peakThreshold * highest;
    const std::size_t pick =
        *std::find_if(keys.begin(), keys.end(), [&](std::size_t k) { return nsdf_[k] >= cutoff; });

    const auto v = detail::parabolic(nsdf_[pick - 1], nsdf_[pick], nsdf_[pick + 1]);
    return detail::finish(cfg_, frame, static_cast<double>(pick) + v.offset, v.value);
}

YinDetector::YinDetector(const DetectorConfig &config)
    : cfg_(config), correlator_(static_cast<std::size_t>(config.window), detail::maxLagFor(config)),
      cmnd_(detail::maxLagFor(config) + 1) {}

PitchResult YinDetector::process(const float *samples, std::size_t count) noexcept {
    const detail::Frame frame = detail::makeFrame(cfg_, samples, count);
    PitchResult silent;
    silent.rmsDb = frame.rmsDb;
    if (frame.rmsDb < cfg_.gateDb || frame.maxLag <= frame.minLag) {
        return silent;
    }

    // Fixed integration length so every lag sums the same number of terms.
    const std::size_t lastLag = frame.maxLag + 1;
    const std::size_t length = frame.count - lastLag;
    correlator_.compute(frame.data, frame.count, length, lastLag);
    const double *r = correlator_.r();
    const float *x = frame.data;

    double head = 0.0;
    for (std::size_t j = 0; j < length; ++j) {
        head += static_cast<double>(x[j]) * x[j];
    }
    double shifted = head;
    double running = 0.0;
    cmnd_[0] = 1.0;
    for (std::size_t tau = 1; tau <= lastLag; ++tau) {
        const double out = x[tau - 1];
        const double in = x[tau + length - 1];
        shifted += in * in - out * out;
        const double d = std::max(0.0, head + shifted - 2.0 * r[tau]);
        running += d;
        cmnd_[tau] = running > 1e-12 ? d * static_cast<double>(tau) / running : 1.0;
    }

    const double threshold = 1.0 - cfg_.clarityThreshold;
    std::size_t pick = 0;
    for (std::size_t tau = frame.minLag; tau <= frame.maxLag; ++tau) {
        if (cmnd_[tau] < threshold) {
            while (tau + 1 <= frame.maxLag && cmnd_[tau + 1] < cmnd_[tau]) {
                ++tau;
            }
            pick = tau;
            break;
        }
    }
    if (pick == 0) {
        pick = frame.minLag;
        for (std::size_t tau = frame.minLag; tau <= frame.maxLag; ++tau) {
            if (cmnd_[tau] < cmnd_[pick]) {
                pick = tau;
            }
        }
    }

    const auto v = detail::parabolic(cmnd_[pick - 1], cmnd_[pick], cmnd_[pick + 1]);
    return detail::finish(cfg_, frame, static_cast<double>(pick) + v.offset, 1.0 - v.value);
}

} // namespace tuner
