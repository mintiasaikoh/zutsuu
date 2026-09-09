// swift-tools-version: 6.2
// /Users/mymac/zutsuu/ios/ZutsuuKit/Package.swift
// 気圧判定（RiskEngine）と個人化回帰（PersonalRisk）を配布する。
// 判定エンジンからUIへの依存を作らず、広告層から健康データ型へ到達させないため。
// 関連: docs/riskengine-api.md, docs/personalrisk-api.md
import PackageDescription

let package = Package(
    name: "ZutsuuKit",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "RiskEngine", targets: ["RiskEngine"]),
        .library(name: "PersonalRisk", targets: ["PersonalRisk"])
    ],
    targets: [
        .target(
            name: "RiskEngine",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(name: "RiskEngineTests", dependencies: ["RiskEngine"]),
        .target(name: "PersonalRisk", dependencies: ["RiskEngine"],
                swiftSettings: [.treatAllWarnings(as: .error)]),
        .testTarget(name: "PersonalRiskTests", dependencies: ["PersonalRisk", "RiskEngine"])
    ],
    // tools-version 6.2 の既定と同じだが、明示しておくことで
    // tools-version を下げた際に言語モードが黙って v5 へ戻るのを防ぐ。
    // `swiftLanguageModes` はターゲットではなくテストにも掛かるパッケージ単位の指定。
    swiftLanguageModes: [.v6]
)
