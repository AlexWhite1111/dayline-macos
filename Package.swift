// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Dayline",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Dayline", targets: ["Dayline"]),
        .executable(name: "dayline-cli", targets: ["DaylineCLI"]),
        .executable(name: "dayline-mcp", targets: ["DaylineMCP"])
    ],
    targets: [
        .target(
            name: "DaylineAutomation",
            path: "Sources/DaylineAutomation",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Dayline",
            dependencies: ["DaylineAutomation"],
            path: "Sources/Dayline",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DaylineCLI",
            dependencies: ["DaylineAutomation"],
            path: "Sources/DaylineCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DaylineMCP",
            dependencies: ["DaylineAutomation"],
            path: "Sources/DaylineMCP",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DaylineTests",
            dependencies: ["Dayline", "DaylineAutomation"],
            path: "Tests/DaylineTests"
        )
    ]
)
