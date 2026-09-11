// /Users/mymac/zutsuu/ios/ZutsuuAds/Sources/ZutsuuAds/AdProvider.swift
// 広告の出し口を 1 枚のプロトコルに閉じ込める（設計書 §8.3）。
// 後からメディエーションへ差し替えても画面側を触らずに済むようにするため。
// 関連: AdMobProvider.swift, docs/plans/2026-09-12-admob-plan4.md
import Foundation

/// 広告ユニット。**本番では AdMob 管理画面の値に差し替える**（Plan 4 の宿題）。
/// 現在は Google 公式のテスト ID。
public enum AdUnitIDs {
    public static let applicationID = "ca-app-pub-3940256099942544~1458002511"
    public static let native = "ca-app-pub-3940256099942544/3986624511"
    public static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    public static let rewarded = "ca-app-pub-3940256099942544/1712485313"
    public static let appOpen = "ca-app-pub-3940256099942544/5575463023"
}

/// 画面が知る必要のある広告の状態と操作。実装は `AdMobProvider`、プレビューやテストでは `NoAdsProvider`。
@MainActor
public protocol AdProvider: AnyObject, Observable {
    /// 同意取得と SDK 初期化が済み、広告を出せる状態か。
    var isReady: Bool { get }
    /// UMP が「プライバシー設定」の再表示を要求しているか（EEA 等）。
    var privacyOptionsRequired: Bool { get }
    /// 同意（UMP）→ ATT → SDK 初期化。メイン画面の描画後に一度だけ呼ぶ。
    func start() async
    func presentPrivacyOptions() async
    /// 準備できていれば表示して true。
    func presentInterstitial() async -> Bool
    func presentAppOpen() async -> Bool
    /// 視聴完了で報酬を得たら true。
    func presentRewarded() async -> Bool
}

/// 広告を出さない実装（プレビュー・テスト・SDK が無いプラットフォーム）。
@MainActor @Observable
public final class NoAdsProvider: AdProvider {
    public private(set) var isReady = false
    public let privacyOptionsRequired = false
    public init() {}
    public func start() async {}
    public func presentPrivacyOptions() async {}
    public func presentInterstitial() async -> Bool { false }
    public func presentAppOpen() async -> Bool { false }
    public func presentRewarded() async -> Bool { false }
}
