// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "skyland-cyberdeck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "skyland-cyberdeck", targets: ["skyland-cyberdeck"]),
        // now playing for the audio deck: loaded by /usr/bin/perl, bundled next to the
        // executable, not linked (Sources/MediaRemoteAdapter/README.md)
        .library(name: "MediaRemoteAdapter", type: .dynamic, targets: ["MediaRemoteAdapter"]),
    ],
    targets: [
        .executableTarget(name: "skyland-cyberdeck", path: "Sources/skyland-cyberdeck"),
        .target(
            name: "MediaRemoteAdapter",
            path: "Sources/MediaRemoteAdapter",
            exclude: ["LICENSE", "README.md"],
            cSettings: [.headerSearchPath("."), .unsafeFlags(["-fobjc-arc", "-fvisibility=default"])], // as upstream: perl finds its functions
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("AppKit"), .linkedFramework("UniformTypeIdentifiers")]
        ),
        .testTarget(name: "skyland-cyberdeckTests", dependencies: ["skyland-cyberdeck"], path: "Tests"),
    ]
)
