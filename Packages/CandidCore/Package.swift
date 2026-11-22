// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CandidCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CandidCore", targets: ["CandidCore"]),
    ],
    targets: [
        .target(name: "CandidCore"),
        .testTarget(name: "CandidCoreTests", dependencies: ["CandidCore"]),
    ]
)
