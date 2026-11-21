// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "PAYELauncher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PAYELauncher", targets: ["PAYELauncher"]),
    ],
    targets: [
        // Logic without UI: finding Basic PAYE Tools, building server commands,
        // running processes, URL policy. Covered by unit tests.
        .target(name: "PAYELauncherCore", swiftSettings: swiftSettings),
        // The AppKit app: window, web view, menus.
        .executableTarget(
            name: "PAYELauncher",
            dependencies: ["PAYELauncherCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PAYELauncherCoreTests",
            dependencies: ["PAYELauncherCore"],
            swiftSettings: swiftSettings
        ),
    ]
)
