#include "tuner/detail/correlator.hpp"

#include <algorithm>
#include <bit>
#include <cassert>
#include <numbers>

namespace tuner::detail {

Fft::Fft(std::size_t n) : n_(n), twiddles_(n / 2), bitReverse_(n) {
    assert(std::has_single_bit(n));
    for (std::size_t k = 0; k < n / 2; ++k) {
        twiddles_[k] = std::polar(1.0, -2.0 * std::numbers::pi * static_cast<double>(k) /
                                           static_cast<double>(n));
    }
    const auto bits = static_cast<unsigned>(std::countr_zero(n));
    for (std::size_t i = 0; i < n; ++i) {
        std::uint32_t rev = 0;
        for (unsigned b = 0; b < bits; ++b) {
            rev |= static_cast<std::uint32_t>((i >> b) & 1u) << (bits - 1u - b);
        }
        bitReverse_[i] = rev;
    }
}

void Fft::forward(std::complex<double> *data) const noexcept { transform(data, false); }

void Fft::inverse(std::complex<double> *data) const noexcept { transform(data, true); }

void Fft::transform(std::complex<double> *data, bool inverse) const noexcept {
    for (std::size_t i = 0; i < n_; ++i) {
        if (i < bitReverse_[i]) {
            std::swap(data[i], data[bitReverse_[i]]);
        }
    }
    for (std::size_t len = 2; len <= n_; len *= 2) {
        const std::size_t half = len / 2;
        const std::size_t step = n_ / len;
        for (std::size_t i = 0; i < n_; i += len) {
            for (std::size_t k = 0; k < half; ++k) {
                const auto w = inverse ? std::conj(twiddles_[k * step]) : twiddles_[k * step];
                const auto u = data[i + k];
                const auto v = data[i + k + half] * w;
                data[i + k] = u + v;
                data[i + k + half] = u - v;
            }
        }
    }
}

namespace {
std::size_t fftSizeFor(std::size_t maxCount, std::size_t maxLag) {
    return std::bit_ceil(maxCount + maxLag + 1);
}
} // namespace

Correlator::Correlator(std::size_t maxCount, std::size_t maxLag)
    : fft_(fftSizeFor(maxCount, maxLag)), a_(fft_.size()), b_(fft_.size()), r_(maxLag + 1) {}

void Correlator::compute(const float *x, std::size_t count, std::size_t prefix,
                         std::size_t maxLag) noexcept {
    assert(maxLag < r_.size() && count + maxLag < fft_.size() && prefix <= count);
    const std::size_t n = fft_.size();
    std::fill(a_.begin(), a_.end(), std::complex<double>{});
    for (std::size_t i = 0; i < prefix; ++i) {
        a_[i] = x[i];
    }
    fft_.forward(a_.data());

    if (prefix == count) {
        for (std::size_t k = 0; k < n; ++k) {
            a_[k] = std::norm(a_[k]);
        }
    } else {
        std::fill(b_.begin(), b_.end(), std::complex<double>{});
        for (std::size_t i = 0; i < count; ++i) {
            b_[i] = x[i];
        }
        fft_.forward(b_.data());
        for (std::size_t k = 0; k < n; ++k) {
            a_[k] = std::conj(a_[k]) * b_[k];
        }
    }

    fft_.inverse(a_.data());
    const double scale = 1.0 / static_cast<double>(n);
    for (std::size_t tau = 0; tau <= maxLag; ++tau) {
        r_[tau] = a_[tau].real() * scale;
    }
}

} // namespace tuner::detail
