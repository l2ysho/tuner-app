// swift-tools-version: 6.2
import PackageDescription

let strictSwift: [SwiftSetting] = [.treatAllWarnings(as: .error)]
let strictC: [CXXSetting] = [.unsafeFlags(["-Wall", "-Wextra", "-Wpedantic", "-Werror"])]

// Dependency direction: TunerDSPC <- TunerCore <- TunerUI / TunerAudio <- App, AUv3.
var targets: [Target] = [
    // The C++ core in /core, reached through symlinks so it lives in one place. Swift only
    // sees the C header, so no target needs C++ interop.
    .target(
        name: "TunerDSPC",
        sources: ["src", "capi"],
        publicHeadersPath: "include",
        cxxSettings: [.headerSearchPath("cxxinclude")] + strictC
    ),
    .target(name: "TunerCore", dependencies: ["TunerDSPC"], swiftSettings: strictSwift),
    .testTarget(name: "TunerCoreTests", dependencies: ["TunerCore"], swiftSettings: strictSwift),
]
var products: [Product] = [.library(name: "TunerCore", targets: ["TunerCore"])]

// TunerUI and TunerAudio need the iOS SDK. `swift test` builds every target, so `just test-core`
// sets TUNERKIT_CORE_ONLY to build and test the platform-independent part alone (also on Linux).
#if os(Linux)
    let coreOnly = true
#else
    let coreOnly = Context.environment["TUNERKIT_CORE_ONLY"] != nil
#endif

if !coreOnly {
    targets += [
        .target(
            name: "TunerUI",
            dependencies: ["TunerCore"],
            resources: [.copy("Resources/Fonts")],
            swiftSettings: strictSwift
        ),
        .target(name: "TunerAudio", dependencies: ["TunerCore"], swiftSettings: strictSwift),
    ]
    products += [
        .library(name: "TunerUI", targets: ["TunerUI"]),
        .library(name: "TunerAudio", targets: ["TunerAudio"]),
    ]
}

let package = Package(
    name: "TunerKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: products,
    targets: targets,
    cxxLanguageStandard: .cxx20
)
