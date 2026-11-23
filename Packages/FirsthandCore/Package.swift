// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FirsthandCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "FirsthandCore", targets: ["FirsthandCore"]),
    ],
    targets: [
        .target(name: "FirsthandCore"),
        .testTarget(name: "FirsthandCoreTests", dependencies: ["FirsthandCore"]),
    ]
)
