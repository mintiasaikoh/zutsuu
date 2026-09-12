// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/NotificationReconciler.swift
// 予約済み通知・新しい予定・台帳を突き合わせ、追加・取消・温存・付け替えを決める。
// 配信済みを再送しない、設定変更を予約に反映する、条件の消えた通知は必ず消す、を 1 箇所で決めるため。
// 関連: NotificationLedger.swift, AlertNotifications.swift, docs/appcore-api.md, docs/riskengine-api.md §6.9
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

/// 入口が過ぎて温存中の起床時通知のうち、静穏時間の変更で発火時刻を動かすもの。
/// 本文の判定はアプリ層が入口時刻の系列から引き直す。
public struct RetimedWakeUp: Sendable, Equatable {
    public let pending: PendingAlert
    public let fireDate: Date

    public init(pending: PendingAlert, fireDate: Date) {
        self.pending = pending
        self.fireDate = fireDate
    }
}

public struct ReconcilePlan: Sendable, Equatable {
    /// `removePendingNotificationRequests(withIdentifiers:)` に渡す識別子。`retime` の分も含む。
    public let cancel: [String]
    /// 新たに `add` する予定。発火時刻順。
    public let add: [ScheduledAlert]
    /// 取り消したうえで発火時刻を変えて登録し直す起床時通知。
    public let retime: [RetimedWakeUp]

    public init(cancel: [String], add: [ScheduledAlert], retime: [RetimedWakeUp] = []) {
        self.cancel = cancel
        self.add = add
        self.retime = retime
    }
}

public enum NotificationReconciler {
    /// iOS の保留中ローカル通知の上限（設計書 §4）。
    public static let pendingLimit = 64
    /// 発火時刻の差がこれ未満なら同じ予約とみなす。
    static let tolerance: TimeInterval = 1

    /// 規則（この順に適用する）:
    ///
    /// 1. 台帳で発火時刻が `now` 以前のエピソードは**配信済み**。新しい予定に同じ識別子があっても追加しない
    ///    （OS の保留一覧からは消えているため、台帳がないと記録・更新のたびに再送する）
    /// 2. 発火時刻が `now` 以前の保留分は対象外（OS が既に配信または破棄している）
    /// 3. 同じ識別子が新しい予定にもある → 発火時刻が同じなら温存。違えば取り消して新しい予定を追加する
    ///    （静穏時間の変更で発火が動いた場合）
    /// 4. 入口が `now` 以前の `.wakeUp` は温存する（規則 2 に対応する新しい予定が現れないため）。
    ///    ただし現在の静穏時間から求めた明けの時刻と発火が違えば、その時刻へ付け替える
    ///    （静穏時間を延ばした・縮めた・無効にした）
    /// 5. それ以外の保留分は取消。条件の消えた通知は外れ通知になり、信頼を最も損なう（設計書 §4）
    /// 6. 新しい `.wakeUp` の発火時刻に、温存・付け替えした `.wakeUp` が既にあれば追加しない
    ///    （同じ朝に 2 件並べない。`AlertScheduler` の集約を予約済み分へ延長する）
    /// 7. 温存 + 付け替え + 追加が上限を超える分は、発火の遅い追加分から落とす
    /// 静穏時間を渡さない版。温存中の起床時通知は付け替えない（設定が分からないため）。
    public static func reconcile(pending: [PendingAlert], scheduled: [ScheduledAlert],
                                 ledger: NotificationLedger = NotificationLedger(),
                                 now: Date) -> ReconcilePlan {
        reconcile(pending: pending, scheduled: scheduled, ledger: ledger, now: now,
                  quietHours: nil, calendar: .current, retimeWakeUps: false)
    }

    /// 静穏時間を渡す版。`quietHours` が nil なら「静穏時間なし」として温存中の起床時通知を直後に鳴らす。
    public static func reconcile(pending: [PendingAlert], scheduled: [ScheduledAlert],
                                 ledger: NotificationLedger, now: Date,
                                 quietHours: QuietHours?, calendar: Calendar) -> ReconcilePlan {
        reconcile(pending: pending, scheduled: scheduled, ledger: ledger, now: now,
                  quietHours: quietHours, calendar: calendar, retimeWakeUps: true)
    }

    private static func reconcile(pending: [PendingAlert], scheduled: [ScheduledAlert],
                                  ledger: NotificationLedger, now: Date, quietHours: QuietHours?,
                                  calendar: Calendar, retimeWakeUps: Bool) -> ReconcilePlan {
        let scheduledByID = Dictionary(scheduled.map { (AlertNotifications.identifier(for: $0), $0) },
                                       uniquingKeysWith: { first, _ in first })
        let delivered = ledger.delivered(now: now)
        var kept = Set<String>()
        var keptWakeUpFireDates = Set<Date>()
        var cancel: [String] = []
        var retime: [RetimedWakeUp] = []

        for request in pending where request.fireDate > now {
            if let same = scheduledByID[request.identifier] {
                if abs(same.fireDate.timeIntervalSince(request.fireDate)) < tolerance {
                    kept.insert(request.identifier)
                    if request.kind == .wakeUp { keptWakeUpFireDates.insert(request.fireDate) }
                } else {
                    cancel.append(request.identifier)
                }
                continue
            }
            let startedWakeUp = request.kind == .wakeUp && request.targetDate <= now
            guard startedWakeUp else {
                cancel.append(request.identifier)
                continue
            }
            let expected = retimeWakeUps
                ? wakeUpFireDate(now: now, quietHours: quietHours, calendar: calendar) : nil
            if let expected, abs(expected.timeIntervalSince(request.fireDate)) >= tolerance {
                cancel.append(request.identifier)
                retime.append(RetimedWakeUp(pending: request, fireDate: expected))
                keptWakeUpFireDates.insert(expected)
            } else {
                kept.insert(request.identifier)
                keptWakeUpFireDates.insert(request.fireDate)
            }
        }

        let additions = scheduled
            .filter { alert in
                let id = AlertNotifications.identifier(for: alert)
                if kept.contains(id) || delivered.contains(id) { return false }
                if alert.kind == .wakeUp && keptWakeUpFireDates.contains(alert.fireDate) { return false }
                return true
            }
            .sorted { $0.fireDate < $1.fireDate }
        let room = max(0, pendingLimit - kept.count - retime.count)
        return ReconcilePlan(cancel: cancel, add: Array(additions.prefix(room)), retime: retime)
    }

    /// 温存中の起床時通知が今の設定で鳴るべき時刻。静穏時間の外なら直後（`AlertScheduler.grace`）。
    /// 明けが求まらない設定（`firstMomentOutside` が nil）なら nil = そのまま温存。
    static func wakeUpFireDate(now: Date, quietHours: QuietHours?, calendar: Calendar) -> Date? {
        guard let quietHours, quietHours.contains(now, calendar: calendar) else {
            return now.addingTimeInterval(AlertScheduler.grace)
        }
        return quietHours.firstMomentOutside(now, calendar: calendar)
    }
}
