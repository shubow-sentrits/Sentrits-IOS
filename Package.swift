// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExplorerLogic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ExplorerLogic", targets: ["ExplorerLogic"])
    ],
    targets: [
        .target(
            name: "ExplorerLogic"
        ),
        .testTarget(
            name: "ExplorerLogicTests",
            dependencies: ["ExplorerLogic"]
        )
    ]
)
