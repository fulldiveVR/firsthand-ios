// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CandidCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CandidCore", targets: ["CandidCore"]),
    ],
    targets: [
        .target(name: "CandidCore"),
        .testTarget(name: "CandidCoreTests", dependencies: ["CandidCore"]),
    ]
)
