// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZutsuuKit",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "RiskEngine", targets: ["RiskEngine"])
    ],
    targets: [
        .target(name: "RiskEngine"),
        .testTarget(name: "RiskEngineTests", dependencies: ["RiskEngine"])
    ]
)
