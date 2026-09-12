// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/NotificationLedger.swift
// アプリ自身が予約した通知の台帳。配信済み（発火時刻が過ぎた）エピソードを覚えておく。
// OS の保留一覧は配信後に消えるため、それだけを見ると同じエピソードを何度でも再予約してしまう（レビュー R01）。
// 関連: NotificationReconciler.swift, docs/appcore-api.md, docs/reviews/2026-09-12-codebase-review.md
import Foundation
import RiskEngine

/// 予約した通知の記録。アプリ層が JSON で永続化し、再予約のたびに `NotificationReconciler` へ渡す。
public struct NotificationLedger: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Hashable {
        public let identifier: String
        public let fireDate: Date
        public let targetDate: Date
        /// `AlertKind` は別モジュールの enum で Codable を合成できないため文字列で持つ。
        private let kindName: String

        public var kind: AlertKind { kindName == "wakeUp" ? .wakeUp : .advance }

        public init(identifier: String, fireDate: Date, targetDate: Date, kind: AlertKind) {
            self.identifier = identifier
            self.fireDate = fireDate
            self.targetDate = targetDate
            kindName = kind == .wakeUp ? "wakeUp" : "advance"
        }
    }

    /// 配信からこれだけ経った記録は捨てる。同じ入口のエピソードが翌日以降に再出現することはない
    /// （識別子に入口の時刻が入るため）ので、台帳が無限に育つのを防ぐだけの値。
    public static let retention: TimeInterval = 24 * 3600

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public func entry(for identifier: String) -> Entry? {
        entries.first { $0.identifier == identifier }
    }

    /// 発火時刻が過ぎた（= OS が配信した、または配信直前の）識別子。
    public func delivered(now: Date) -> Set<String> {
        Set(entries.filter { $0.fireDate <= now }.map(\.identifier))
    }

    /// 予約したものを記録する。同じ識別子は置き換える（付け替え時）。
    public func recording(_ alerts: [ScheduledAlert]) -> NotificationLedger {
        var next = self
        for alert in alerts {
            let entry = Entry(identifier: AlertNotifications.identifier(for: alert),
                              fireDate: alert.fireDate, targetDate: alert.targetDate, kind: alert.kind)
            next.entries.removeAll { $0.identifier == entry.identifier }
            next.entries.append(entry)
        }
        return next
    }

    /// 取り消したものを忘れる。取り消した予約は配信されていないので、再予約を妨げてはいけない。
    public func removing(_ identifiers: [String]) -> NotificationLedger {
        let ids = Set(identifiers)
        var next = self
        next.entries.removeAll { ids.contains($0.identifier) }
        return next
    }

    /// 古い記録を捨てる。
    public func pruned(now: Date) -> NotificationLedger {
        var next = self
        next.entries.removeAll { max($0.fireDate, $0.targetDate) < now.addingTimeInterval(-Self.retention) }
        return next
    }
}
