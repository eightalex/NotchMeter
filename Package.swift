// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchMeter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchMeter",
            path: "Sources/NotchMeter",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("AppKit"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
