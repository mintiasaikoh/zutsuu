// /Users/mymac/zutsuu/ios/ZutsuuAds/Sources/AdPolicy/RewardUnlocks.swift
// リワード動画で期限付きに解放する機能と、その期限（設計書 §8.2 Tier 3 の表）。
// 期限付きにするのは再収益化のためだが、短すぎると嫌がらせになるので表の値を上限とする。
// 関連: docs/plans/2026-09-12-admob-plan4.md, 設計書 §8.2
import Foundation

/// 解放対象。rawValue は保存キーなので変更禁止。
public enum RewardPerk: String, Codable, Sendable, CaseIterable {
    case correlationReport
    case extraLocation
    case detailedForecast
    case logGraph

    /// 設計書 §8.2 の期限。
    public var duration: TimeInterval {
        switch self {
        case .correlationReport: 7 * 86_400
        case .extraLocation: 30 * 86_400
        case .detailedForecast: 24 * 3600
        case .logGraph: 7 * 86_400
        }
    }
}

/// 解放の期限表。値型なので呼び出し側が保存する。
public struct RewardUnlocks: Codable, Sendable, Equatable {
    public var expiry: [RewardPerk: Date]

    public init(expiry: [RewardPerk: Date] = [:]) {
        self.expiry = expiry
    }

    public func isUnlocked(_ perk: RewardPerk, now: Date) -> Bool {
        guard let until = expiry[perk] else { return false }
        return now < until
    }

    /// 視聴完了で期限を延ばす。残りがあっても「今から期間分」に置き換える（延長の重ね掛けはしない）。
    public func granting(_ perk: RewardPerk, now: Date) -> RewardUnlocks {
        var next = self
        next.expiry[perk] = now.addingTimeInterval(perk.duration)
        return next
    }

    public func remaining(_ perk: RewardPerk, now: Date) -> TimeInterval? {
        guard let until = expiry[perk], until > now else { return nil }
        return until.timeIntervalSince(now)
    }
}
