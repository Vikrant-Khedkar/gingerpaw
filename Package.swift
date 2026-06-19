// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlowOSS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlowOSS", targets: ["FlowOSSApp"]),
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
    ]
)
