// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EditingKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EditingKit", targets: ["EditingKit"])
    ],
    dependencies: [
        .package(path: "../USDCore"),
        .package(path: "../ValidationKit"),
        .package(path: "../MeshKit")
    ],
    targets: [
        .target(name: "EditingKit", dependencies: ["USDCore", "ValidationKit", "MeshKit"], path: "Sources/EditingKit"),
        .testTarget(name: "EditingKitTests", dependencies: ["EditingKit"], path: "Tests/EditingKitTests"),
    ]
)
