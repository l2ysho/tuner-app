# Guitar Tuner — project handoff

> App name: **Freetuner** (set once, in `APP_DISPLAY_NAME` in `apple/project.yml`; code and repo still say "tuner"). Bundle ID `sk.riviatech.freetuner`.
> Owner: Richard (senior full-stack dev, new to native iOS — explain Swift/Xcode specifics briefly when they matter).
> Design canvas (source of truth for UI): https://claude.ai/artifact/Vp4Bv4bNyARAeXGfT2cEz4 → page **"Final — main screen"**.

## 0. Dev loop (read first)

- After every change run the fastest relevant check: `just test-dsp` (C++ core, ~5 s) or `just test-core` (Swift core, ~2 s). UI changes: `just test-app`.
- Run `just check` before saying a task is done. Never report done with red checks.
- Output is quiet: one `ok` line per step; on failure only the relevant lines plus the log path (`build/logs/<step>.log`).
- A PostToolUse hook (`.claude/hooks/post-edit.sh`) formats and lints each file you edit. Exit 2 = fix what it printed.
- See the UI: `just screenshot state=flat` (flat | sharp | intune | idle | sweep | live), then read `artifacts/screen.png`.
- Snapshot failures write diffs to `artifacts/snapshots/`; open the PNGs. Re-record with `just record-snapshots` and look at every new image before committing it.
- Xcode MCP (`.mcp.json`, `xcrun mcpbridge`) needs Xcode running with the project open and MCP enabled in Xcode → Settings → Intelligence.
- TestFlight: bump `CURRENT_PROJECT_VERSION` in `apple/project.yml`, then `just upload`. Signs with an App Store Connect API key: `ASC_KEY_ID` + `ASC_ISSUER_ID` in the untracked `.env`, key at `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`.

Rules:
- No logic in `apple/Tuner/` (app target): wiring only.
- No AVFoundation outside `TunerAudio` (the AUv3 extension excepted).
- Audio render path (sink block, `tdsp_*_process/push`): no allocation, no locks, no Objective-C messaging, no main-actor isolation.
- Never hand-edit `.pbxproj`; it is generated and not committed. Change `apple/project.yml`, run `just gen`.
- DSP changes need a golden test. UI changes need an updated snapshot that you have looked at.

## 1. What we are building

A clean, ad-free guitar tuner for iPhone and iPad (iOS 26+, Liquid Glass), later iPhone Duo (foldable), Mac, an AUv3 plugin and Android.

- **Free**, no ads, no account, no tracking. Audio is analysed on device and never recorded or sent.
- Portfolio piece: code quality, tests and CI matter as much as features.
- Competitors with the same "honest tuner" pitch exist (OpenTuner, iontuner, Tuneo). We win on **detection quality, design and device coverage** (iPad, Duo, AUv3).

## 2. Architecture

```
repo/
├── CLAUDE.md  justfile  .clang-format .clang-tidy .swift-format .swiftlint.yml
├── core/                     # C++20 DSP library, CMake, zero Apple dependencies (also the Android/JNI entry)
│   ├── include/tuner/ src/   # MPM + YIN detectors, Tuner state machine
│   ├── capi/                 # tuner_dsp_c.h: the C ABI Swift and JNI use
│   ├── tests/                # Catch2 + synthetic signals; golden, timing, no-allocation tests
│   └── tools/bench/          # CLI: detector over WAV/synthetic input, CSV out
├── apple/
│   ├── project.yml           # XcodeGen manifest, the only source of the Xcode project
│   ├── Tuner/                # app target: @main + wiring, assets
│   ├── AudioUnit/            # AUv3 extension (pass-through placeholder, NOT embedded in the app)
│   ├── SnapshotTests/        # swift-snapshot-testing, reference PNGs in __Snapshots__
│   └── TunerKit/             # SwiftPM package with almost all Swift code
│       ├── Sources/TunerDSPC # C target: core/ sources via symlinks, exposes only the C header
│       ├── Sources/TunerCore # tunings, note math, TunerDisplay, AudioSource, TunerEngine (Linux-safe)
│       ├── Sources/TunerUI   # SwiftUI views, TunerModel, bundled fonts (no AVFoundation)
│       └── Sources/TunerAudio# MicrophoneSource (AVAudioEngine), permission
├── fixtures/                 # WAV recordings `<note>_<desc>.wav` (git LFS); tests skip while empty
└── .github/workflows/ci.yml  # Linux: test-dsp + test-core. macOS (xcode-27 runner, Xcode 27.2 = release Xcode): just check
```

Dependency direction: core ← TunerDSPC ← TunerCore ← TunerUI / TunerAudio ← App, AUv3.

- Swift reaches C++ only through the **C ABI** (`core/capi`), not C++ interop mode, so no Swift target needs interop flags and JNI can use the same surface.
- `core/` builds and tests without Xcode (CMake). `TUNERKIT_CORE_ONLY=1 swift test` builds only the platform-independent targets (macOS and Linux).
- Audio: `AudioSource` (protocol in TunerCore) writes into a lock-free `SampleRing`; `TunerEngine` analyses it on a serial queue every 512 samples. `MicrophoneSource` is the real input; `SyntheticSource` drives demo mode and tests.

## 3. DSP spec (`core/`)

### Input
- Mono float32, **48 kHz** (accept 44.1 kHz too; sample rate is a parameter, never hard-coded).
- Analysis window **4096 samples** (~85 ms @ 48 kHz) — enough periods for low strings down to **B1 ≈ 61.7 Hz** (drop / 7-string).
- Hop **512–1024 samples** (~10–20 ms) → UI updates at 50–100 Hz.

### Algorithms
- **MPM (McLeod Pitch Method)** as the primary detector; **YIN** implemented too for comparison in the bench tool.
- Parabolic interpolation of the peak for sub-sample accuracy.
- **Clarity / confidence** threshold (start at ~0.9 for MPM) → below it the reading is "unvoiced".
- **Level floor** −80 dBFS, fixed (no user setting): noise is rejected by clarity, not level. A user noise gate was tried and dropped.
- **Octave-error guard**: in auto string mode, prefer the candidate closest to a string of the current tuning.

### Post-processing (`Tuner` state machine)
- Median of last 5 readings + adaptive EMA on cents: alpha 0.03 for jitter, up to 1.0 for a change ≥ 10 ¢ (cubic in between). Steady display beats speed on tiny peg turns (~0.5 s to settle a 3 ¢ step).
- `cents = 1200 · log2(f / f_target)`, A4 reference default **440 Hz** (range 415–466, 1 Hz steps).
- **Lock**: |cents| ≤ tolerance (default **±3 ¢**, options ±1/±3/±5) held for ≥ 200 ms → `locked = true` (marks the string as tuned).
- Note naming: sharps or flats (user setting).
- Auto string detection: nearest string of the active tuning; manual string selection overrides it.
- Idle: no voiced reading for > 1 s → idle state.

### Suggested public API (adjust freely, keep it small)

```cpp
namespace tuner {
struct DetectorConfig { float sampleRate = 48000; int window = 4096; float clarityThreshold = 0.9f; float gateDb = -80; };
struct PitchResult    { float hz; float clarity; float rmsDb; bool voiced; };

class PitchDetector {               // MPM; YinDetector has the same interface
public:
  explicit PitchDetector(DetectorConfig);
  PitchResult process(const float* samples, size_t count) noexcept;   // no allocation
};

struct TunerState { int midi; int stringIndex; float cents; bool voiced; bool locked; bool idle; };

class Tuner {                       // smoothing, lock, string matching
public:
  void setTuning(const std::vector<float>& stringHz);
  void setReference(float a4Hz);
  void setTolerance(float cents);
  TunerState push(const PitchResult&, double timestampSec);
};
}
```

### Quality targets (M1 acceptance)
| Test | Target |
|---|---|
| Clean synthetic sine + harmonic-rich saw, E2…E4 and B1 | error ≤ **±1 ¢** |
| Missing-fundamental signal (low E) | no octave error |
| White/pink noise at −20 dB SNR | no false voiced readings above gate |
| Detune sweep ±50 ¢ | monotonic, no jumps > 2 ¢ between hops |
| Time to stable reading after pluck | ≤ **150 ms** |
| CPU | `process()` on a 4096 window well under 1 ms on iPhone 17 Pro |

The bench tool prints per-file CSV (time, hz, cents, clarity, voiced) for MPM and YIN side by side.
Real recordings go to `fixtures/` (Richard will record each string clean + with distortion on an iPhone 17 Pro); start with synthetic signals until they exist.

## 4. App spec (`apple/`)

- **SwiftUI**, iOS/iPadOS **26+**, iPhone + iPad (universal). Test device: iPhone 17 Pro.
- State via `@Observable` model; audio on its own thread, UI reads the latest `TunerState` (no locks on the audio thread).
- Persistence: `TunerModel` reads and writes `UserDefaults` itself (one key per setting, custom tunings as JSON). Do not add `@AppStorage` for the same keys. Declared in `apple/Tuner/PrivacyInfo.xcprivacy` (UserDefaults CA92.1, system boot time 35F9.1); update it when adding a required-reason API.
- No haptics (tried and dropped: not useful while playing). Optional "keep screen awake".
- Appearance: System (default) / Light / Dark in Settings, set on the windows; every colour comes from `Palette` (light/dark pairs in `Theme.swift`).
- `NSMicrophoneUsageDescription`: "The tuner listens to find the note you play. Nothing is recorded or sent."

### Screens (see canvas, page "Final — main screen")
1. **Main tuner**: dial with no box — big note letter (+ small octave) inside a thin arc of **21 ticks** (−50…+50 ¢, 5 ¢ per tick, ±80° spread). Only lit ticks take the state colour; centre tick lit when in tune. One status line under it: `−12¢ ▲` / `+18¢ ▼` / `IN TUNE` / `PLAY A STRING`. **The whole screen background tints** with the state. Six string keys at the bottom (active key = ink fill, green dot = already tuned). Bottom **trio toolbar**: A4 circle (`440`) · tuning pill (`Standard EADGBE ⌃⌄`) · settings circle.
2. **Idle**: neutral background, grey `–`, no lit ticks, no active key.
3. **Microphone**: first-launch screen ("Let's hear your guitar" · "Continue" · "NOTHING IS RECORDED OR SENT"; never "Allow", App Review rejects it) and denied screen ("Microphone is off" · "Open Settings" · "Not now").
4. **Tuning picker** (sheet): Guitar / Bass / Ukulele segmented control; presets Standard, Drop D, Half Step Down, Full Step Down, Drop C, DADGAD, Open G. Plain rows with hairline dividers, orange check on the selected one.
5. **Settings** (sheet): A4 pitch stepper, in-tune range (±1/±3/±5 ¢), note names (sharps/flats), Tools → intonation check, appearance (system / light / dark), meter (dial / strobe), keep screen awake.
6. **Trial features** (Nov 2026, kept only if they survive testing): chromatic mode (picker segment), ALL TUNED status, custom tunings (picker → New tuning; long-press to edit/delete), 12th-fret intonation check, strobe meter. Reference tone was tried and dropped. Footer: `NO ADS · NO TRACKING · NO ACCOUNT`.

### Layout rule for larger screens
Same structure everywhere: dial centred in free space, keys + toolbar anchored at the bottom, no split at a fold.
Dial ≈ 62 % of screen width (max 520 pt); keys + toolbar ≈ 74 % (max 620 pt). Phone: dial 350 pt, keys 64 pt tall.

### Design tokens
| Token | Value |
|---|---|
| body / panel / ink | `#E8E8E3` / `#F4F4F0` / `#1D1D1B` |
| grey / border | `#9A9A94` / `#C9C9C2` |
| flat / sharp / in tune (marks) | `#2F6FED` / `#FF5A00` / `#2E9E4F` |
| flat / sharp / in tune (text) | `#1F55C4` / `#A93A00` / `#1E7A3A` |
| screen tint flat / sharp / in tune / idle | `#E4E9F2` / `#F3E7DF` / `#E2EEE4` / `#E8E8E3` |
| unlit tick / centre tick | ink at 13 % / 32 % opacity |
| fonts | **Inter Tight** (UI, note letter), **IBM Plex Mono** (values, labels) — both OFL, bundle them |
| radii | keys 8 pt, sheets system, toolbar items full capsule |

### Liquid Glass rules (Apple HIG)
- Glass **only on the floating control layer**: the bottom toolbar items and sheet toolbar buttons. Use system components (`.glassEffect()`, `.buttonStyle(.glass)` / `.glassProminent`).
- **No glass on content** (dial, keys, lists) and **never glass on glass**.
- Tint only the primary action (Done in sheets).
- Respect Reduce Transparency / Reduce Motion / Increase Contrast; support Dynamic Type for labels.

## 5. Milestones

| # | Scope | Done when |
|---|---|---|
| **M0** | Repo scaffold, CMake + Catch2, CI (build + tests on macOS runner), README | `ctest` green in CI |
| **M1** | DSP core: MPM, YIN, note math, `Tuner` state machine, synthetic test signals, bench CLI | All quality targets in §3 pass |
| **M2** | iOS app shell: audio capture, SwiftUI main screen (flat / sharp / in tune / idle), mic permission flow | Tunes a real guitar on iPhone 17 Pro |
| **M3** | Tuning picker + settings sheets, persistence | All settings work and survive relaunch |
| **M4** | iPad (landscape + portrait) layouts | Matches canvas |
| **M5** | Polish: accessibility, app icon, App Store metadata, TestFlight | TestFlight build |
| Later | AUv3 plugin, iPhone Duo layouts, strobe mode, Mac target, Android (Kotlin + Oboe + JNI) | — |

**Start with M0 → M1.** Detection quality is the biggest risk; UI comes after the core is proven.

## 6. Conventions
- C++20, `-Wall -Wextra -Werror`, clang-format (LLVM base, 4-space indent). No exceptions or allocation in `process()`.
- Swift 6 language mode, strict concurrency, warnings are errors. swift-format + SwiftLint (`just fmt`, `just lint`). No third-party UI libraries.
- Small PRs, conventional commits (`feat:`, `fix:`, `test:`, `chore:`).
- Every DSP change comes with a test; keep the bench CSV output stable so runs can be diffed.

## 7. Open questions
- App Store name: "Freetuner" is free as an exact name, but a tuner called "Freetune" exists and the name is generic. Have a fallback ready if App Review rejects it (shortlist: Beatless, Plumb, Zeroed, Unfret).
- App icon: decided (Nov 2026) — strobe, five green bars with the centre one long, `apple/Tuner/AppIcon.icon` (Icon Composer, layered for Liquid Glass; edit it in Icon Composer). Render with `"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" apple/Tuner/AppIcon.icon --export-image --output-file out.png --platform iOS --rendition Default --width 512 --height 512 --scale 1` (`xcrun ictool` is a different tool).
- Real string recordings for `fixtures/` — pending.
- iPhone Duo point sizes are estimates (474×696 closed, 904×640 open) — confirm in the simulator.
