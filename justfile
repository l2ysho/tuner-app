# Single entry point for every check. Output is quiet: one line per step, details only on failure.
# Full logs: build/logs/<step>.log.

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load

q := justfile_directory() / "tools/quiet"
dd := justfile_directory() / "build/xcode"
dsp_build := justfile_directory() / "build/dsp-asan"
project := "apple/Tuner.xcodeproj"
swift_paths := "apple/Tuner apple/AudioUnit apple/SnapshotTests apple/TunerKit/Package.swift apple/TunerKit/Sources/TunerCore apple/TunerKit/Sources/TunerUI apple/TunerKit/Sources/TunerAudio apple/TunerKit/Tests"
cpp_files := "git ls-files 'core/*.cpp' 'core/*.hpp' 'core/*.h'"
clang_tidy := `brew --prefix llvm 2>/dev/null || echo /usr`  / "bin/clang-tidy"

# Lint, then every test layer, stopping at the first failure.
check: lint test-dsp test-core build-app test-app
    @echo "check passed"

# Format Swift and C++ in place.
fmt:
    @swift format format -i -r {{swift_paths}}
    @{{cpp_files}} | xargs clang-format -i

lint: _configure-dsp
    @{{q}} swift-format swift format lint --strict -r {{swift_paths}}
    @{{q}} swiftlint swiftlint lint --strict --quiet
    @{{q}} clang-format bash -o pipefail -c "{{cpp_files}} | xargs clang-format --dry-run --Werror"
    @{{q}} clang-tidy {{clang_tidy}} -p {{dsp_build}} --quiet {{ if os() == "macos" { "--extra-arg=-isysroot$(xcrun --show-sdk-path)" } else { "" } }} core/src/*.cpp core/capi/*.cpp

# C++ core with ASan + UBSan: golden, C API, timing and no-allocation tests.
test-dsp: _configure-dsp
    @{{q}} test-dsp bash -o pipefail -c "cmake --build {{dsp_build}} && ctest --test-dir {{dsp_build}} -j8 --output-on-failure"

# Platform-independent Swift (TunerDSPC + TunerCore). Runs on macOS and Linux.
test-core:
    @{{q}} test-core env TUNERKIT_CORE_ONLY=1 swift test --package-path apple/TunerKit

# Regenerate the Xcode project from apple/project.yml.
gen:
    @xcodegen generate --quiet --spec apple/project.yml

build-app: gen
    @{{q}} build-app bash -o pipefail -c "xcodebuild build -project {{project}} -scheme Tuner -destination id=$(tools/simulator) -derivedDataPath {{dd}} CODE_SIGNING_ALLOWED=NO | xcbeautify --quiet --disable-colored-output"

# Snapshot tests on the simulator. Failure diffs: artifacts/snapshots/.
test-app: gen
    @rm -rf artifacts/snapshots
    @{{q}} test-app bash -o pipefail -c "TEST_RUNNER_SNAPSHOT_ARTIFACTS={{justfile_directory()}}/artifacts/snapshots xcodebuild test -project {{project}} -scheme Tuner -destination id=$(tools/simulator) -derivedDataPath {{dd}} CODE_SIGNING_ALLOWED=NO | xcbeautify --quiet --disable-colored-output" || { ls artifacts/snapshots/*/*.png 2>/dev/null | sed 's/^/diff: /' >&2; exit 1; }

# Re-record every snapshot. Look at each new PNG before committing it.
record-snapshots: gen
    @{{q}} record-snapshots bash -o pipefail -c "TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all xcodebuild test -project {{project}} -scheme Tuner -destination id=$(tools/simulator) -derivedDataPath {{dd}} CODE_SIGNING_ALLOWED=NO | xcbeautify --quiet --disable-colored-output" || true
    @git status --short apple/SnapshotTests

# Launch the app in the simulator and save artifacts/screen.png.
# state: flat | sharp | intune | idle | sweep (synthetic tone) or live (microphone).
screenshot state="flat": build-app
    #!/usr/bin/env bash
    set -euo pipefail
    udid=$(tools/simulator)
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl install "$udid" "{{dd}}/Build/Products/Debug-iphonesimulator/Tuner.app"
    args=(); [ "{{state}}" = live ] || args=(-demo "{{state}}")
    xcrun simctl launch --terminate-running-process "$udid" sk.riviatech.freetuner "${args[@]}" >/dev/null
    sleep 3
    mkdir -p artifacts
    xcrun simctl io "$udid" screenshot artifacts/screen.png >/dev/null 2>&1
    echo "artifacts/screen.png ({{state}})"

# Signed App Store build uploaded to TestFlight. Bump CURRENT_PROJECT_VERSION in project.yml first.
# Needs ASC_KEY_ID and ASC_ISSUER_ID (App Store Connect API key), e.g. in an untracked .env.
upload: gen
    @[ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] || { echo "set ASC_KEY_ID and ASC_ISSUER_ID in .env"; exit 1; }
    @rm -rf build/release
    @{{q}} archive xcodebuild archive -project {{project}} -scheme Tuner -configuration Release -destination generic/platform=iOS -archivePath build/release/Tuner.xcarchive CODE_SIGNING_ALLOWED=NO
    @{{q}} upload xcodebuild -exportArchive -archivePath build/release/Tuner.xcarchive -exportPath build/release/upload -exportOptionsPlist apple/ExportOptions.plist -allowProvisioningUpdates -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"

_configure-dsp:
    @[ -f {{dsp_build}}/build.ninja ] || {{q}} configure-dsp cmake -S core -B {{dsp_build}} -G Ninja -DCMAKE_BUILD_TYPE=Debug -DTUNER_SANITIZE=ON -DTUNER_BUILD_TOOLS=OFF
