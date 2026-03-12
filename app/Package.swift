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
        .executableTarget(
            name: "CentralStation",
            dependencies: ["Yams", "SwiftTerm"],
            path: "Sources/CentralStation"
        ),
        .testTarget(
            name: "CentralStationTests",
            dependencies: [
                "Yams",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/CentralStationTests"
        ),
    ]
)
