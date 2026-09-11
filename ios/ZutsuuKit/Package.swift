// swift-tools-version: 6.2
// /Users/mymac/zutsuu/ios/ZutsuuKit/Package.swift
// 気圧判定（RiskEngine）、体調入力UI（KiabouUI）、個人化回帰（PersonalRisk）、
// アプリ層の純粋ロジック（AppCore）を配布する。
// 判定エンジンからUIへの依存を作らず、広告層から健康データ型へ到達させないため。
// 関連: docs/riskengine-api.md, docs/kiabou-integration.md, docs/personalrisk-api.md, docs/appcore-api.md
import PackageDescription

let package = Package(
    name: "ZutsuuKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "RiskEngine", targets: ["RiskEngine"]),
        .library(name: "KiabouUI", targets: ["KiabouUI"]),
        .library(name: "PersonalRisk", targets: ["PersonalRisk"]),
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    targets: [
        .target(
            name: "RiskEngine",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(name: "RiskEngineTests", dependencies: ["RiskEngine"]),
        .target(name: "KiabouUI", resources: [.process("Resources")],
                swiftSettings: [.treatAllWarnings(as: .error)]),
        .testTarget(name: "KiabouUITests", dependencies: ["KiabouUI"]),
        .target(name: "PersonalRisk", dependencies: ["RiskEngine"],
                swiftSettings: [.treatAllWarnings(as: .error)]),
        .testTarget(name: "PersonalRiskTests", dependencies: ["PersonalRisk", "RiskEngine"]),
        .target(name: "AppCore", dependencies: ["RiskEngine"], resources: [.process("Resources")],
                swiftSettings: [.treatAllWarnings(as: .error)]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "RiskEngine"])
    ],
    // tools-version 6.2 の既定と同じだが、明示しておくことで
    // tools-version を下げた際に言語モードが黙って v5 へ戻るのを防ぐ。
    // `swiftLanguageModes` はターゲットではなくパッケージ単位の指定で、
    // テストターゲットにも同じモードが掛かる。
    swiftLanguageModes: [.v6]
)
