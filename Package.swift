// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Veil",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Veil", targets: ["Veil"])],
    targets: [
        // Foundation-only logic: filter compiler, URL parsing, local stores. Portable + unit-testable.
        .target(name: "VeilCore"),
        // The AppKit/WebKit application. No third-party dependencies.
        .executableTarget(name: "Veil", dependencies: ["VeilCore"]),
        .testTarget(name: "VeilCoreTests", dependencies: ["VeilCore"]),
    ]
)
