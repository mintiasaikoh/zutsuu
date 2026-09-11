// /Users/mymac/zutsuu/ios/ZutsuuAds/Sources/AdPolicy/InterstitialGate.swift
// インタースティシャルの頻度制御（設計書 §8.2 Tier 2）。
// 予期しない全画面広告は AdMob のポリシー違反であり、収益とコンプライアンスの両面で制御が必須なため。
// 関連: AppOpenGate.swift, docs/plans/2026-09-12-admob-plan4.md
import Foundation

/// 遷移ごとに呼び、表示してよいかと次の状態を返す。状態は呼び出し側が保存する（Codable）。
public struct InterstitialGate: Sendable {
    public struct State: Codable, Sendable, Equatable {
        /// 起動後の遷移回数。最初の遷移では出さない。
        public var transitionsSinceLaunch: Int
        /// 前回表示からの遷移回数。
        public var transitionsSinceShown: Int
        public var lastShown: Date?
        /// その暦日に出した回数と、その日付（yyyyMMdd 相当のキー）。
        public var shownToday: Int
        public var dayKey: String

        public init(transitionsSinceLaunch: Int = 0, transitionsSinceShown: Int = 0, lastShown: Date? = nil,
                    shownToday: Int = 0, dayKey: String = "") {
            self.transitionsSinceLaunch = transitionsSinceLaunch
            self.transitionsSinceShown = transitionsSinceShown
            self.lastShown = lastShown
            self.shownToday = shownToday
            self.dayKey = dayKey
        }
    }

    public let transitionsPerAd: Int
    public let minimumInterval: TimeInterval
    public let dailyLimit: Int
    public let calendar: Calendar

    /// 設計書 §8.2: 4 回ごと、3 分以上、1 日 6 回まで。
    public init(transitionsPerAd: Int = 4, minimumInterval: TimeInterval = 3 * 60, dailyLimit: Int = 6,
                calendar: Calendar = .current) {
        self.transitionsPerAd = transitionsPerAd
        self.minimumInterval = minimumInterval
        self.dailyLimit = dailyLimit
        self.calendar = calendar
    }

    /// 画面遷移を 1 回記録する。通知経由の起動による遷移は `countsAsTransition: false` で渡し、数えない。
    public func transition(_ state: State, now: Date, countsAsTransition: Bool = true) -> (show: Bool, state: State) {
        var next = Self.rolledOver(state, now: now, calendar: calendar)
        guard countsAsTransition else { return (false, next) }
        next.transitionsSinceLaunch += 1
        next.transitionsSinceShown += 1
        let notFirst = next.transitionsSinceLaunch > 1
        let dueByCount = next.transitionsSinceShown >= transitionsPerAd
        let dueByTime = next.lastShown.map { now.timeIntervalSince($0) >= minimumInterval } ?? true
        let underDaily = next.shownToday < dailyLimit
        guard notFirst, dueByCount, dueByTime, underDaily else { return (false, next) }
        next.transitionsSinceShown = 0
        next.lastShown = now
        next.shownToday += 1
        return (true, next)
    }

    /// 起動時に呼ぶ。遷移の数え直しを始め、日次の回数と前回表示は保つ。
    public func launched(_ state: State, now: Date) -> State {
        var next = Self.rolledOver(state, now: now, calendar: calendar)
        next.transitionsSinceLaunch = 0
        next.transitionsSinceShown = 0
        return next
    }

    private static func rolledOver(_ state: State, now: Date, calendar: Calendar) -> State {
        let key = dayKey(now, calendar: calendar)
        guard state.dayKey != key else { return state }
        var next = state
        next.dayKey = key
        next.shownToday = 0
        return next
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
