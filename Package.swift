// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FlowBox",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SharedCore",
            path: "Sources/SharedCore"
        ),
        .executableTarget(
            name: "FlowBox",
            dependencies: ["SharedCore"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "FlowBoxExt",
            dependencies: ["SharedCore"],
            path: "Sources/Extension"
        ),
        .testTarget(
            name: "FlowBoxTests",
            dependencies: ["SharedCore"],
            path: "Tests/FlowBoxTests"
        ),
        .executableTarget(
            name: "FlowBoxTestRunner",
            dependencies: ["SharedCore"],
            path: "Sources/TestRunner"
        ),
    ]
)
