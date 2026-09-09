// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/NotificationReconciler.swift
// 予約済み通知と新しい予定を突き合わせ、追加・取消・温存を決める。
// 再スケジュールで入口の過ぎた起床時通知を消さず、条件の消えた通知は必ず消すため。
// 関連: AlertNotifications.swift, docs/appcore-api.md, docs/riskengine-api.md §6.9, 設計書 §4
import Foundation
import RiskEngine

/// `UNUserNotificationCenter` から読み戻した保留中の予約 1 件。
/// アプリ層が識別子と `userInfo` から復元する。
public struct PendingAlert: Sendable, Hashable {
    public let identifier: String
    public let fireDate: Date
    public let kind: AlertKind
    public let targetDate: Date

    public init(identifier: String, fireDate: Date, kind: AlertKind, targetDate: Date) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.kind = kind
        self.targetDate = targetDate
    }
}

public struct ReconcilePlan: Sendable, Equatable {
    /// `removePendingNotificationRequests(withIdentifiers:)` に渡す識別子。
    public let cancel: [String]
    /// 新たに `add` する予定。発火時刻順。
    public let add: [ScheduledAlert]

    public init(cancel: [String], add: [ScheduledAlert]) {
        self.cancel = cancel
        self.add = add
    }
}

public enum NotificationReconciler {
    /// iOS の保留中ローカル通知の上限（設計書 §4）。
    public static let pendingLimit = 64

    /// 規則（この順に適用する）:
    ///
    /// 1. 発火時刻が `now` 以前の保留分は対象外（OS が既に配信または破棄している）
    /// 2. 同じ識別子が新しい予定にもある → 何もしない。付け替えると同じ通知が
    ///    消えて出直すだけで、ユーザーに見える差はない
    /// 3. **入口が `now` 以前の `.wakeUp` は温存する。** 規則 1 が入口の過ぎた
    ///    エピソードを返さないため、新しい予定には現れない。無条件に置き換えると
    ///    起床時通知が静かに消える（`riskengine-api.md` §6.9）
    /// 4. それ以外の保留分は取消。予報が変わって条件が消えた通知は外れ通知になり、
    ///    信頼を最も損なう（設計書 §4）
    /// 5. 温存 + 追加が上限を超える分は、発火の遅い追加分から落とす
    public static func reconcile(pending: [PendingAlert], scheduled: [ScheduledAlert],
                                 now: Date) -> ReconcilePlan {
        let scheduledByID = Dictionary(scheduled.map { (AlertNotifications.identifier(for: $0), $0) },
                                       uniquingKeysWith: { first, _ in first })
        var kept = Set<String>()
        var cancel: [String] = []

        for request in pending where request.fireDate > now {
            let sameEpisode = scheduledByID[request.identifier] != nil
            let startedWakeUp = request.kind == .wakeUp && request.targetDate <= now
            if sameEpisode || startedWakeUp {
                kept.insert(request.identifier)
            } else {
                cancel.append(request.identifier)
            }
        }

        let additions = scheduled
            .filter { !kept.contains(AlertNotifications.identifier(for: $0)) }
            .sorted { $0.fireDate < $1.fireDate }
        let room = max(0, pendingLimit - kept.count)
        return ReconcilePlan(cancel: cancel, add: Array(additions.prefix(room)))
    }
}
