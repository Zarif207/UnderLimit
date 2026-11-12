// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UnderLimit",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "FitKit"),
        .executableTarget(
            name: "fit",
            dependencies: [
                "FitKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "fitcheck", dependencies: ["FitKit"]),
    ]
)
