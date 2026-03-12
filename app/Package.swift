// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CentralStation",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "release/6.2"),
    ],
    targets: [
        .target(
            name: "CentralStationCore",
            dependencies: ["Yams"],
            path: "Sources/CentralStationCore"
        ),
        .executableTarget(
            name: "CentralStation",
            dependencies: ["CentralStationCore", "SwiftTerm"],
            path: "Sources/CentralStation"
        ),
        .testTarget(
            name: "CentralStationTests",
            dependencies: [
                "CentralStationCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/CentralStationTests"
        ),
    ]
)
