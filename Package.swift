// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Slide",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CMultitouch",
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("MultitouchSupport"),
            ]
        ),
        .target(name: "SlideCore"),
        .executableTarget(name: "Slide", dependencies: ["CMultitouch", "SlideCore"]),
        .testTarget(name: "SlideCoreTests", dependencies: ["SlideCore"]),
    ]
)
