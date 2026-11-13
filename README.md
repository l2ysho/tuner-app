# tuner

A clean, ad-free guitar tuner for iPhone and iPad. No ads, no account, no tracking. Audio is analysed on device and never recorded or sent.

## Layout

| Path | Contents |
|---|---|
| `core/` | C++20 DSP library (pitch detection, tuner state machine), CMake + Catch2 |
| `apple/` | SwiftUI app and Swift package wrapping `core/` (not yet created) |
| `fixtures/` | WAV recordings for tests, stored with Git LFS |

## Build and test the core

Needs CMake ≥ 3.25, a C++20 compiler and (optionally) Ninja.

```bash
cmake -S core -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
```

Catch2 is fetched at configure time unless an installed Catch2 3.x is found.

## Bench

Runs MPM and YIN side by side and prints CSV (one row per hop). Timing goes to stderr.

```bash
./build/tools/bench/tuner_bench --target 82.41 fixtures/e2_clean.wav
./build/tools/bench/tuner_bench synth:saw:82.41:2 synth:pink:0:1
```

Synth inputs: `synth:<sine|saw|missing|pluck|white|pink>:<hz>:<seconds>`.

## Format

```bash
clang-format -i $(git ls-files 'core/*.cpp' 'core/*.hpp')
```
