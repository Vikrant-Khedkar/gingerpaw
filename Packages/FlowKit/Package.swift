// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlowKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentMCP", targets: ["AgentMCP"]),
        .library(name: "AgentNotifications", targets: ["AgentNotifications"]),
        .library(name: "AgentWorkspace", targets: ["AgentWorkspace"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "Audio", targets: ["Audio"]),
        .library(name: "Dictation", targets: ["Dictation"]),
        .library(name: "Hotkeys", targets: ["Hotkeys"]),
        .library(name: "Overlay", targets: ["Overlay"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "TextInsertion", targets: ["TextInsertion"]),
        .library(name: "TextProcessing", targets: ["TextProcessing"]),
        .library(name: "Transcription", targets: ["Transcription"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.25.9"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.2.7"),  // SPIKE: Ghostty terminal
    ],
    targets: [
        .target(name: "AgentMCP"),
        .target(name: "AgentNotifications"),
        .target(name: "AgentWorkspace", dependencies: [
            "AgentMCP",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
            .product(name: "GhosttyTerminal", package: "libghostty-spm"),  // SPIKE
        ]),
        .target(name: "Settings"),
        .target(name: "Permissions"),
        .target(name: "Audio"),
        .target(name: "Transcription", dependencies: [
            "Settings",
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
        ]),
        .target(name: "TextInsertion"),
        .target(name: "Hotkeys", dependencies: ["Settings"]),
        .target(name: "Overlay", dependencies: ["Dictation"]),
        .target(
            name: "TextProcessing",
            dependencies: [
                "Dictation",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ]
        ),
        .target(
            name: "Dictation",
            dependencies: ["Audio", "Settings", "TextInsertion", "Transcription"]
        ),
        .target(
            name: "AppCore",
            dependencies: ["AgentNotifications", "AgentWorkspace", "Dictation", "Hotkeys", "Overlay", "Permissions", "Settings", "TextProcessing"]
        ),
        .testTarget(name: "DictationTests", dependencies: ["Dictation"]),
        .testTarget(name: "TextInsertionTests", dependencies: ["TextInsertion"]),
        .testTarget(name: "AgentWorkspaceTests", dependencies: ["AgentWorkspace"]),
    ]
)
