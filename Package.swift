// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IaNano",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ia-nano", targets: ["NanoClient"]),
                 .executable(name: "ia-nano-gui", targets: ["IaNano"])],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", from: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.23.2")
    ],
    targets: [
        .target(name: "NanoIPC"),
        .executableTarget(name: "NanoClient", dependencies: ["NanoIPC"]),
        .testTarget(name: "NanoIPCTests", dependencies: ["NanoIPC"]),
        .target(name: "NanoCore", dependencies: ["NanoIPC",
            .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
            .product(name: "TreeSitterRuby", package: "tree-sitter-ruby"),
            .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript")
        ]),
        .executableTarget(name: "IaNano", dependencies: ["NanoCore"]),
        .testTarget(name: "NanoCoreTests", dependencies: ["NanoCore"]),
        .testTarget(name: "NanoUITests", dependencies: ["IaNano"])
    ]
)
