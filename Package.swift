// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
        .executable(name: "QuotaBar", targets: ["QuotaBar"]),
        .executable(name: "quota-bar", targets: ["QuotaBarCLI"])
    ],
    targets: [
        .target(name: "QuotaBarCore", path: "Sources/QuotaBarCore"),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarCore"],
            path: "Sources/QuotaBar"
        ),
        .executableTarget(
            name: "QuotaBarCLI",
            dependencies: ["QuotaBarCore"],
            path: "Sources/QuotaBarCLI"
        ),
        .testTarget(
            name: "QuotaBarTests",
            dependencies: ["QuotaBar", "QuotaBarCore"],
            path: "Tests/QuotaBarTests"
        )
    ]
)
