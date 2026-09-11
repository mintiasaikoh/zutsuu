// /Users/mymac/zutsuu/ios/ZutsuuAds/Sources/AdPolicy/AppOpenGate.swift
// App Open 広告の可否（設計書 §8.2）。コールドスタートでは出さず、復帰時のみ 4 時間以上あける。
// 起動体感を殺さないため。
// 関連: InterstitialGate.swift, docs/plans/2026-09-12-admob-plan4.md
import Foundation

public struct AppOpenGate: Sendable {
    public let minimumInterval: TimeInterval

    public init(minimumInterval: TimeInterval = 4 * 3600) {
        self.minimumInterval = minimumInterval
    }

    /// フォアグラウンド復帰時に呼ぶ。コールドスタート（`isColdStart`）と通知経由の復帰では出さない。
    public func shouldShow(lastShown: Date?, now: Date, isColdStart: Bool, launchedFromNotification: Bool) -> Bool {
        guard !isColdStart, !launchedFromNotification else { return false }
        guard let lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= minimumInterval
    }
}
