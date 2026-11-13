# tuner

A clean, ad-free guitar tuner for iPhone and iPad. No ads, no account, no tracking. Audio is analysed on device and never recorded or sent.

## Layout

| Path | Contents |
|---|---|
| `core/` | C++20 DSP library (pitch detection, tuner state machine), CMake + Catch2 |
| `apple/` | SwiftUI app (`Tuner/`), `TunerCore` Swift package wrapping `core/` via Swift/C++ interop |
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

## iOS app

Needs Xcode 26+ (iOS 26 SDK). The Xcode project is generated from `apple/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); regenerate after adding or removing files:

```bash
cd apple && xcodegen generate
```

```bash
swift test --package-path apple/TunerCore
```

```bash
xcodebuild test -project apple/Tuner.xcodeproj -scheme Tuner -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`apple/TunerCore/Sources/TunerCoreCxx/{src,include/tuner}` are symlinks into `core/`, so the C++ lives in one place.

Debug builds accept `-demo <flat|sharp|intune|idle|sweep>` as a launch argument: a synthetic tone replaces the microphone (useful in the simulator and for screenshots).

### Fonts

The design uses Inter Tight and IBM Plex Mono (both OFL). They are not in the repo yet; without them the app falls back to SF Pro / SF Mono. To bundle them, put these files in `apple/Tuner/Fonts/` and regenerate the project:
`InterTight-{Medium,SemiBold,Bold}.ttf`, `IBMPlexMono-{Regular,Medium,SemiBold}.ttf`.

## Format

```bash
clang-format -i $(git ls-files 'core/*.cpp' 'core/*.hpp')
```
