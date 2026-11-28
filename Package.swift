// swift-tools-version:6.0
import PackageDescription

// ShotkeeperCore must build and test on Linux: Foundation only, no AppKit/SwiftUI/ImageIO.
// SQLite comes from the system: `import SQLite3` on Apple platforms, the CSQLite module map on Linux.
let package = Package(
    name: "Shotkeeper",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ShotkeeperCore", targets: ["ShotkeeperCore"]),
        .executable(name: "shotkeeper-cli", targets: ["shotkeeper-cli"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3",
                       providers: [.apt(["libsqlite3-dev"])]),
        .target(
            name: "ShotkeeperCore",
            dependencies: [.target(name: "CSQLite", condition: .when(platforms: [.linux]))]
        ),
        .executableTarget(name: "shotkeeper-cli", dependencies: ["ShotkeeperCore"]),
        .testTarget(
            name: "ShotkeeperCoreTests",
            dependencies: ["ShotkeeperCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
