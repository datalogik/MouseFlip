// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseFlip",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MouseFlip", targets: ["MouseFlip"])],
    targets: [
        .target(name: "ScrollPolicy"),
        .executableTarget(name: "MouseFlip", dependencies: ["ScrollPolicy"]),
        .testTarget(name: "ScrollPolicyTests", dependencies: ["ScrollPolicy"])
    ]
)
