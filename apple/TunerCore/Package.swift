// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TunerCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TunerCore", targets: ["TunerCore"]),
    ],
    targets: [
        // core/ sources, reached through symlinks so the C++ stays in one place.
        .target(
            name: "TunerCoreCxx",
            path: "Sources/TunerCoreCxx",
            sources: ["src"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "TunerCore",
            dependencies: ["TunerCoreCxx"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .testTarget(
            name: "TunerCoreTests",
            dependencies: ["TunerCore"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
