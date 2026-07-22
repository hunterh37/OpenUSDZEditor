// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RenderKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RenderKit", targets: ["RenderKit"])
    ],
    dependencies: [
        // RenderKit sits just above AgentMCP: it provides the concrete
        // `RenderExecuting` backends (native SceneKit + usdrecord) that both the
        // CLI-hosted and App-hosted MCP servers inject. Depends only on AgentMCP
        // (for the RenderExecuting protocol) + Apple frameworks — no USDBridge.
        .package(path: "../AgentMCP"),
    ],
    targets: [
        .target(name: "RenderKit", dependencies: ["AgentMCP"], path: "Sources"),
        .testTarget(name: "RenderKitTests", dependencies: ["RenderKit"], path: "Tests"),
    ]
)
