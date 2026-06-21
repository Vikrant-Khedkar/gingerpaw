// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlowOSS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlowOSS", targets: ["FlowOSSApp"]),
        .executable(name: "flowoss", targets: ["flowoss"]),
    ],
    dependencies: [
        .package(path: "Packages/FlowKit"),
    ],
    targets: [
        .executableTarget(
            name: "FlowOSSApp",
            dependencies: [
                .product(name: "AppCore", package: "FlowKit"),
            ],
            path: "App/Sources"
        ),
        .executableTarget(
            name: "flowoss",
            dependencies: [
                .product(name: "AgentNotifications", package: "FlowKit"),
                .product(name: "AgentMCP", package: "FlowKit"),
            ],
            path: "CLI/Sources"
        ),
    ]
)
