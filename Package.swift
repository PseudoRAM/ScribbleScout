// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotebookCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "NotebookCore", path: "ScribbleScout/Models"),
        .testTarget(name: "NotebookCoreTests", dependencies: ["NotebookCore"])
    ]
)
