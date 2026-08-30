// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZutsuuKit",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "RiskEngine", targets: ["RiskEngine"])
    ],
    targets: [
        .target(
            name: "RiskEngine",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(name: "RiskEngineTests", dependencies: ["RiskEngine"])
    ],
    // tools-version 6.2 の既定と同じだが、明示しておくことで
    // tools-version を下げた際に言語モードが黙って v5 へ戻るのを防ぐ。
    // `swiftLanguageModes` はターゲットではなくパッケージ単位の指定で、
    // テストターゲットにも同じモードが掛かる。
    swiftLanguageModes: [.v6]
)
