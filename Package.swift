// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacTab",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacTab", targets: ["MacTab"])],
    targets: [
        .executableTarget(name: "MacTab"),
        .testTarget(name: "MacTabTests", dependencies: ["MacTab"])
    ]
)
