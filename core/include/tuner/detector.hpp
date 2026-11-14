#pragma once

#include "tuner/detail/correlator.hpp"

#include <cstddef>
#include <vector>

namespace tuner {

struct DetectorConfig {
    float sampleRate = 48000.0f;
    int window = 4096;
    float minHz = 50.0f;
    float maxHz = 1400.0f;
    float clarityThreshold = 0.9f;
    float gateDb = -50.0f;
    float peakThreshold = 0.9f; // MPM: first key maximum within this ratio of the highest
};

struct PitchResult {
    float hz = 0.0f;
    float clarity = 0.0f;
    float rmsDb = -120.0f;
    bool voiced = false;
};

namespace detail {
struct Frame {
    const float *data;
    std::size_t count;
    std::size_t minLag;
    std::size_t maxLag;
    float rmsDb;
};
Frame makeFrame(const DetectorConfig &cfg, const float *samples, std::size_t count) noexcept;
std::size_t maxLagFor(const DetectorConfig &cfg) noexcept;
} // namespace detail

// McLeod Pitch Method. process() does not allocate.
class PitchDetector {
  public:
    explicit PitchDetector(const DetectorConfig &config = {});
    // Analyses the last config.window samples (or all of them if fewer).
    PitchResult process(const float *samples, std::size_t count) noexcept;
    const DetectorConfig &config() const noexcept { return cfg_; }

  private:
    DetectorConfig cfg_;
    detail::Correlator correlator_;
    std::vector<double> nsdf_;
    std::vector<std::size_t> keys_; // sized once: one key per lobe at most, so never grows
};

// YIN (de Cheveigné & Kawahara 2002), same interface, used for comparison.
class YinDetector {
  public:
    explicit YinDetector(const DetectorConfig &config = {});
    PitchResult process(const float *samples, std::size_t count) noexcept;
    const DetectorConfig &config() const noexcept { return cfg_; }

  private:
    DetectorConfig cfg_;
    detail::Correlator correlator_;
    std::vector<double> cmnd_;
};

} // namespace tuner
