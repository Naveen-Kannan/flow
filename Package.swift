// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "flow",
    platforms: [.macOS(.v14)],
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
    dependencies: [
        // Pin compatible dependencies for this Mac's Swift 6.1 toolchain.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.12.4"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.6"),
    ],
    targets: [
        .target(
            name: "Flow",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
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
