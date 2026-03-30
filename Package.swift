// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "flow",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "Flow",
            targets: ["Flow"]
        ),
        .executable(
            name: "flowctl",
            targets: ["flowctl"]
        ),
    ],
    targets: [
        .target(
            name: "Flow"
        ),
        .executableTarget(
            name: "flowctl",
            dependencies: ["Flow"]
        ),
        .testTarget(
            name: "FlowTests",
            dependencies: ["Flow"]
        )
    ],
    swiftLanguageModes: [.v5]
)
