// swift-tools-version: 6.2
// /Users/mymac/zutsuu/ios/ZutsuuAds/Package.swift
// 広告（AdMob）を ZutsuuKit から切り離した別パッケージ。
// 広告側から健康データ型へ型レベルで到達できないようにするため（設計書 §3、§8）。
// 関連: docs/plans/2026-09-12-admob-plan4.md, ../ZutsuuKit/Package.swift
import PackageDescription

let package = Package(
    name: "ZutsuuAds",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AdPolicy", targets: ["AdPolicy"]),
        .library(name: "ZutsuuAds", targets: ["ZutsuuAds"])
    ],
    dependencies: [
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", from: "13.9.0"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-user-messaging-platform.git", from: "3.1.0")
    ],
    targets: [
        // 頻度制御と解放期限。SDK に依存せず macOS で swift test できる。
        .target(name: "AdPolicy", swiftSettings: [.treatAllWarnings(as: .error)]),
        .testTarget(name: "AdPolicyTests", dependencies: ["AdPolicy"]),
        // SDK ラッパー。iOS でだけ SDK を結びつけ、他では空のモジュールになる。
        .target(
            name: "ZutsuuAds",
            dependencies: [
                "AdPolicy",
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads",
                         condition: .when(platforms: [.iOS])),
                .product(name: "GoogleUserMessagingPlatform",
                         package: "swift-package-manager-google-user-messaging-platform",
                         condition: .when(platforms: [.iOS]))
            ],
            resources: [.process("Resources")],
            // SDK の delegate 型は Sendable でないものが多く、v6 の厳格検査では書けない箇所がある。
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ],
    swiftLanguageModes: [.v6]
)
