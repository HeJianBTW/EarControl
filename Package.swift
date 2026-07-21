// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EarControl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EarControl",
            path: "Sources/EarControl",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "EarControlTests",
            dependencies: ["EarControl"],
            path: "Tests/EarControlTests"
        )
    ]
)
