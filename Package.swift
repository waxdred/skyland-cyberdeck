// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "skyland-cyberdeck",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "skyland-cyberdeck", path: "Sources/skyland-cyberdeck"),
        .testTarget(name: "skyland-cyberdeckTests", dependencies: ["skyland-cyberdeck"], path: "Tests"),
    ]
)
