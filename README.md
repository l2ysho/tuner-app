# tuner

A clean, ad-free guitar tuner for iPhone and iPad. No ads, no account, no tracking. Audio is analysed on device and never recorded or sent.

## Setup

macOS with Xcode 26+ (iOS 26 SDK), then:

```bash
brew install just xcodegen swiftlint xcbeautify llvm cmake ninja
```

## Commands

| Command | What it does |
|---|---|
| `just check` | lint → test-dsp → test-core → build-app → test-app, stops at the first failure |
| `just test-dsp` | C++ core with ASan/UBSan: golden, C API, timing, no-allocation tests |
| `just test-core` | Swift core (`TunerDSPC` + `TunerCore`), also on Linux |
| `just test-app` | snapshot tests on the simulator; diffs in `artifacts/snapshots/` |
| `just lint` / `just fmt` | swift-format, SwiftLint, clang-format, clang-tidy |
| `just gen` | generate `apple/Tuner.xcodeproj` from `apple/project.yml` (not committed) |
| `just screenshot state=flat` | run the app in the simulator, save `artifacts/screen.png` |
| `just upload` | signed App Store build to TestFlight |

Layout and rules: see `CLAUDE.md`.

## Bench

Runs MPM and YIN side by side and prints CSV (one row per hop). Timing goes to stderr.

```bash
./build/tools/bench/tuner_bench --target 82.41 fixtures/e2_clean.wav
./build/tools/bench/tuner_bench synth:saw:82.41:2 synth:pink:0:1
```

Synth inputs: `synth:<sine|saw|missing|pluck|white|pink>:<hz>:<seconds>`.

## iOS app

Debug builds accept `-demo <flat|sharp|intune|idle|sweep>` as a launch argument: a synthetic tone replaces the microphone.

### Fonts

`apple/TunerKit/Sources/TunerUI/Resources/Fonts/` bundles Inter Tight and IBM Plex Mono (both OFL, licences next to the files). Plex Mono is the static release from the Google Fonts repo. Inter Tight ships only as a variable font there, so the Medium, SemiBold and Bold files are static instances made with `fonttools varLib.instancer --update-name-table`. TunerUI registers them at runtime, so previews and snapshot tests use them too. If a font is missing, the UI falls back to SF Pro / SF Mono.

## Format

```bash
just fmt
```
