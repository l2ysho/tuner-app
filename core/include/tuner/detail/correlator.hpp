#pragma once

#include <complex>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace tuner::detail {

// Radix-2 complex FFT. All memory is allocated in the constructor.
class Fft {
  public:
    explicit Fft(std::size_t n);
    void forward(std::complex<double> *data) const noexcept;
    void inverse(std::complex<double> *data) const noexcept; // unscaled
    std::size_t size() const noexcept { return n_; }

  private:
    void transform(std::complex<double> *data, bool inverse) const noexcept;

    std::size_t n_;
    std::vector<std::complex<double>> twiddles_;
    std::vector<std::uint32_t> bitReverse_;
};

// Linear cross-correlation r(tau) = sum_{j < prefix} x[j] * x[j + tau] via FFT.
// prefix == count gives the plain autocorrelation.
class Correlator {
  public:
    Correlator(std::size_t maxCount, std::size_t maxLag);
    void compute(const float *x, std::size_t count, std::size_t prefix,
                 std::size_t maxLag) noexcept;
    const double *r() const noexcept { return r_.data(); }

  private:
    Fft fft_;
    std::vector<std::complex<double>> a_;
    std::vector<std::complex<double>> b_;
    std::vector<double> r_;
};

} // namespace tuner::detail
