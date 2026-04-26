// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LaunchOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LaunchOS", targets: ["LaunchOS"])
    ],
    targets: [
        .executableTarget(
            name: "LaunchOS",
            path: "Sources/LaunchOS",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
