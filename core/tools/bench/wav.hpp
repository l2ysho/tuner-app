#pragma once

#include <cstdint>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace bench {

struct Audio {
    std::vector<float> samples; // mono
    float sampleRate = 0.0f;
};

// Reads PCM 16/24/32-bit integer or 32-bit float WAV, mixed down to mono.
inline Audio readWav(const std::string &path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        throw std::runtime_error("cannot open " + path);
    }
    std::vector<char> bytes((std::istreambuf_iterator<char>(in)), {});
    auto u16 = [&](std::size_t at) {
        return static_cast<std::uint16_t>(static_cast<std::uint8_t>(bytes[at]) |
                                          static_cast<std::uint8_t>(bytes[at + 1]) << 8);
    };
    auto u32 = [&](std::size_t at) {
        return u16(at) | static_cast<std::uint32_t>(u16(at + 2)) << 16;
    };

    if (bytes.size() < 12 || std::memcmp(bytes.data(), "RIFF", 4) != 0 ||
        std::memcmp(bytes.data() + 8, "WAVE", 4) != 0) {
        throw std::runtime_error(path + ": not a RIFF/WAVE file");
    }

    std::uint16_t format = 0, channels = 0, bits = 0;
    std::uint32_t rate = 0;
    std::size_t dataAt = 0, dataSize = 0;
    for (std::size_t at = 12; at + 8 <= bytes.size();) {
        const std::uint32_t size = u32(at + 4);
        if (std::memcmp(bytes.data() + at, "fmt ", 4) == 0) {
            format = u16(at + 8);
            channels = u16(at + 10);
            rate = u32(at + 12);
            bits = u16(at + 22);
            if (format == 0xFFFE && size >= 40) {
                format = u16(at + 32); // WAVE_FORMAT_EXTENSIBLE sub-format
            }
        } else if (std::memcmp(bytes.data() + at, "data", 4) == 0) {
            dataAt = at + 8;
            dataSize = std::min<std::size_t>(size, bytes.size() - dataAt);
        }
        at += 8 + size + (size & 1u);
    }
    const bool isFloat = format == 3 && bits == 32;
    const bool isPcm = format == 1 && (bits == 16 || bits == 24 || bits == 32);
    if (dataAt == 0 || channels == 0 || !(isFloat || isPcm)) {
        throw std::runtime_error(path + ": unsupported WAV format");
    }

    const std::size_t bytesPerSample = bits / 8;
    const std::size_t frames = dataSize / (bytesPerSample * channels);
    Audio audio;
    audio.sampleRate = static_cast<float>(rate);
    audio.samples.resize(frames);
    for (std::size_t f = 0; f < frames; ++f) {
        double sum = 0.0;
        for (std::size_t c = 0; c < channels; ++c) {
            const std::size_t at = dataAt + (f * channels + c) * bytesPerSample;
            if (isFloat) {
                float v;
                std::memcpy(&v, bytes.data() + at, 4);
                sum += v;
            } else {
                std::int32_t v = 0;
                for (std::size_t b = 0; b < bytesPerSample; ++b) {
                    v |= static_cast<std::int32_t>(static_cast<std::uint8_t>(bytes[at + b]))
                         << (8 * b);
                }
                const int shift = 32 - static_cast<int>(bits);
                v = static_cast<std::int32_t>(static_cast<std::uint32_t>(v) << shift) >> shift;
                sum += v / static_cast<double>(1u << (bits - 1));
            }
        }
        audio.samples[f] = static_cast<float>(sum / channels);
    }
    return audio;
}

} // namespace bench
