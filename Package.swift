// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nomen",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NomenCore", path: "Sources/Core"),
        .executableTarget(
            name: "Nomen",
            dependencies: ["NomenCore"],
            path: "Sources",
            exclude: ["Core"],
            linkerSettings: [
                .unsafeFlags(["-framework", "AppKit"]),
                .unsafeFlags(["-framework", "Vision"]),
                .unsafeFlags(["-framework", "ServiceManagement"]),
            ]
        ),
        .testTarget(
            name: "NomenTests",
            dependencies: ["NomenCore"],
            path: "Tests"
        )
    ]
)
