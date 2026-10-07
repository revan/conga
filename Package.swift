// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conga",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CMultitouch",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("MultitouchSupport"),
            ]
        ),
        .target(name: "CongaCore"),
        .executableTarget(name: "Conga", dependencies: ["CMultitouch", "CongaCore"]),
        .testTarget(name: "CongaCoreTests", dependencies: ["CongaCore"]),
    ]
)
