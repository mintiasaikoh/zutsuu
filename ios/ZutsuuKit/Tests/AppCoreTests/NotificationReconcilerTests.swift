// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/AppCoreTests/NotificationReconcilerTests.swift
// 予約済み通知の温存・取消・追加の判断を検証する。
// 再スケジュールで起床時通知が消えず、条件の消えた通知は必ず消えることを固定するため。
// 関連: ../../Sources/AppCore/NotificationReconciler.swift, docs/riskengine-api.md §6.9
import Testing
import Foundation
import AppCore
import RiskEngine

@Suite("予約済み通知の突き合わせ")
struct NotificationReconcilerTests {

    private func pending(_ alert: ScheduledAlert) -> PendingAlert {
        PendingAlert(identifier: AlertNotifications.identifier(for: alert),
                     fireDate: alert.fireDate, kind: alert.kind, targetDate: alert.targetDate)
    }

    @Test("同じエピソードの予約は付け替えない")
    func sameEpisodeIsLeftAlone() {
        let existing = alert(kind: .advance, fire: utc(10, 12, 30), target: utc(10, 14))
        let recomputed = alert(kind: .advance, fire: utc(10, 12, 30), target: utc(10, 14), score: 9)
        let plan = NotificationReconciler.reconcile(pending: [pending(existing)],
                                                    scheduled: [recomputed], now: utc(10, 9))
        #expect(plan.cancel.isEmpty)
        #expect(plan.add.isEmpty)
    }

    /// 予報が変わって条件が消えた通知は外れ通知になる。必ず消す。
    @Test("新しい予定に無い予約は取り消す")
    func vanishedEpisodeIsCancelled() {
        let existing = alert(kind: .advance, fire: utc(10, 12, 30), target: utc(10, 14))
        let plan = NotificationReconciler.reconcile(pending: [pending(existing)],
                                                    scheduled: [], now: utc(10, 9))
        #expect(plan.cancel == [AlertNotifications.identifier(for: existing)])
        #expect(plan.add.isEmpty)
    }

    @Test("入口がずれた予約は取り消して新しい予定を追加する")
    func shiftedEpisodeIsReplaced() {
        let existing = alert(kind: .advance, fire: utc(10, 12, 30), target: utc(10, 14))
        let shifted = alert(kind: .advance, fire: utc(10, 13, 30), target: utc(10, 15))
        let plan = NotificationReconciler.reconcile(pending: [pending(existing)],
                                                    scheduled: [shifted], now: utc(10, 9))
        #expect(plan.cancel == [AlertNotifications.identifier(for: existing)])
        #expect(plan.add == [shifted])
    }

    /// §6.9: 就寝中の再スケジュールでは規則 1 が入口の過ぎたエピソードを返さない。
    /// 発火がまだ未来の起床時通知は温存する。
    @Test("入口が過ぎた起床時通知は新しい予定に無くても温存する")
    func startedWakeUpIsPreserved() {
        let wakeUp = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: utc(10, 3))
        let plan = NotificationReconciler.reconcile(pending: [pending(wakeUp)],
                                                    scheduled: [], now: utc(10, 5))
        #expect(plan.cancel.isEmpty)
        #expect(plan.add.isEmpty)
    }

    /// 入口がまだ未来の起床時通知は温存の対象外。条件が消えたなら取り消す。
    @Test("入口が未来の起床時通知は通常どおり取り消される")
    func futureWakeUpIsNotPreserved() {
        let wakeUp = alert(kind: .wakeUp, fire: utc(11, 8, 30), target: utc(11, 3))
        let plan = NotificationReconciler.reconcile(pending: [pending(wakeUp)],
                                                    scheduled: [], now: utc(10, 20))
        #expect(plan.cancel == [AlertNotifications.identifier(for: wakeUp)])
    }

    @Test("発火時刻が過ぎた予約は温存も取消もしない")
    func firedRequestsAreIgnored() {
        let fired = alert(kind: .advance, fire: utc(10, 8), target: utc(10, 9, 30))
        let plan = NotificationReconciler.reconcile(pending: [pending(fired)],
                                                    scheduled: [], now: utc(10, 12))
        #expect(plan.cancel.isEmpty)
        #expect(plan.add.isEmpty)
    }

    @Test("追加は発火時刻順で、温存分と合わせて上限64件を超えない")
    func additionsRespectPendingLimit() {
        let preserved = (0..<10).map { day in
            alert(kind: .wakeUp, fire: utc(11 + day, 8, 30), target: utc(10, 3))
        }
        // 温存判定は入口 <= now なので、入口は全て過去に置く。識別子を分けるため入口を 1 分ずつずらす。
        let pendingAlerts = preserved.enumerated().map { index, alert in
            PendingAlert(identifier: "kept-\(index)", fireDate: alert.fireDate,
                         kind: .wakeUp, targetDate: utc(10, 3, index))
        }
        let scheduled = (0..<70).map { hour in
            alert(kind: .advance, fire: utc(12).addingTimeInterval(TimeInterval(hour) * 3600),
                  target: utc(12, 2).addingTimeInterval(TimeInterval(hour) * 3600))
        }.shuffled()
        let plan = NotificationReconciler.reconcile(pending: pendingAlerts,
                                                    scheduled: scheduled, now: utc(10, 5))
        #expect(plan.cancel.isEmpty)
        #expect(plan.add.count == NotificationReconciler.pendingLimit - 10)
        #expect(plan.add.map(\.fireDate) == plan.add.map(\.fireDate).sorted())
        #expect(plan.add.first?.fireDate == utc(12))
    }
}

// MARK: - 台帳・設定変更・同じ朝の集約（レビュー R01 / R02 / R05）

@Suite("配信済みと設定変更の突き合わせ")
struct NotificationReconcilerLedgerTests {
    private func pending(_ alert: ScheduledAlert) -> PendingAlert {
        PendingAlert(identifier: AlertNotifications.identifier(for: alert),
                     fireDate: alert.fireDate, kind: alert.kind, targetDate: alert.targetDate)
    }
    private let quiet = QuietHours(start: 22, end: 8.5)

    /// R01: 12:30 に配信した 14:00 の事前通知は、12:45 の再計算で同じエピソードが
    /// 「直後に鳴らす」形で返ってきても再予約しない。
    @Test("配信済みのエピソードは再計算で戻ってきても追加しない")
    func deliveredEpisodeIsNotReadded() {
        let delivered = alert(kind: .advance, fire: utc(10, 12, 30), target: utc(10, 14))
        let ledger = NotificationLedger().recording([delivered])
        let recomputed = alert(kind: .advance, fire: utc(10, 12, 46), target: utc(10, 14))
        let plan = NotificationReconciler.reconcile(pending: [], scheduled: [recomputed],
                                                    ledger: ledger, now: utc(10, 12, 45),
                                                    quietHours: quiet, calendar: utcCalendar)
        #expect(plan.add.isEmpty)
        #expect(plan.cancel.isEmpty)
    }

    /// 台帳にあっても発火がまだ未来で保留一覧に無い（OS 側で失われた）なら追加してよい。
    @Test("未配信の記録は再予約を妨げない")
    func undeliveredLedgerEntryDoesNotBlock() {
        let planned = alert(kind: .advance, fire: utc(10, 12, 30), target: utc(10, 14))
        let ledger = NotificationLedger().recording([planned])
        let plan = NotificationReconciler.reconcile(pending: [], scheduled: [planned],
                                                    ledger: ledger, now: utc(10, 9),
                                                    quietHours: quiet, calendar: utcCalendar)
        #expect(plan.add == [planned])
    }

    /// R02: 同じエピソードでも発火時刻が変わったなら付け替える。
    @Test("同じ識別子でも発火時刻が変われば取り消して追加する")
    func changedFireDateIsReplaced() {
        let existing = alert(kind: .advance, fire: utc(10, 8, 30), target: utc(10, 9))
        let moved = alert(kind: .advance, fire: utc(10, 8, 45), target: utc(10, 9))
        let plan = NotificationReconciler.reconcile(pending: [pending(existing)], scheduled: [moved],
                                                    ledger: NotificationLedger(), now: utc(10, 1),
                                                    quietHours: quiet, calendar: utcCalendar)
        #expect(plan.cancel == [AlertNotifications.identifier(for: existing)])
        #expect(plan.add == [moved])
    }

    /// R02: 01:00 の事象を 08:30 に知らせる予約があり、03:00 に静穏時間の終了を 10:00 へ延ばした。
    @Test("温存中の起床時通知は静穏時間の変更に合わせて付け替える")
    func preservedWakeUpFollowsQuietHoursChange() {
        let wakeUp = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: utc(10, 1))
        let plan = NotificationReconciler.reconcile(pending: [pending(wakeUp)], scheduled: [],
                                                    ledger: NotificationLedger(), now: utc(10, 3),
                                                    quietHours: QuietHours(start: 22, end: 10),
                                                    calendar: utcCalendar)
        #expect(plan.cancel == [AlertNotifications.identifier(for: wakeUp)])
        #expect(plan.retime.map(\.fireDate) == [utc(10, 10)])
        #expect(plan.add.isEmpty)
    }

    @Test("静穏時間を無効にしたら温存中の起床時通知は直後に鳴らす")
    func disablingQuietHoursFiresPreservedWakeUpSoon() {
        let wakeUp = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: utc(10, 1))
        let plan = NotificationReconciler.reconcile(pending: [pending(wakeUp)], scheduled: [],
                                                    ledger: NotificationLedger(), now: utc(10, 3),
                                                    quietHours: nil, calendar: utcCalendar)
        #expect(plan.retime.map(\.fireDate) == [utc(10, 3).addingTimeInterval(AlertScheduler.grace)])
    }

    @Test("静穏時間が変わっていなければ温存中の起床時通知に触らない")
    func unchangedQuietHoursLeavesWakeUpAlone() {
        let wakeUp = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: utc(10, 1))
        let plan = NotificationReconciler.reconcile(pending: [pending(wakeUp)], scheduled: [],
                                                    ledger: NotificationLedger(), now: utc(10, 3),
                                                    quietHours: quiet, calendar: utcCalendar)
        #expect(plan.cancel.isEmpty && plan.retime.isEmpty && plan.add.isEmpty)
    }

    /// R05: 01:00 の乱れを 08:30 に知らせる予約が温存されているとき、03:00 の再計算で
    /// 05:00 の乱れが同じ 08:30 の起床時通知として返っても、2 件目を足さない。
    @Test("同じ朝の起床時通知は温存分があれば追加しない")
    func sameMorningWakeUpIsNotDuplicated() {
        let kept = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: utc(10, 1))
        let later = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: utc(10, 5))
        let plan = NotificationReconciler.reconcile(pending: [pending(kept)], scheduled: [later],
                                                    ledger: NotificationLedger(), now: utc(10, 3),
                                                    quietHours: quiet, calendar: utcCalendar)
        #expect(plan.add.isEmpty)
        #expect(plan.cancel.isEmpty)
    }

    @Test("台帳は配信済みを識別し、取消で忘れ、古い記録を捨てる")
    func ledgerLifecycle() {
        let a = alert(kind: .advance, fire: utc(10, 12, 30), target: utc(10, 14))
        let b = alert(kind: .wakeUp, fire: utc(11, 8, 30), target: utc(11, 3))
        var ledger = NotificationLedger().recording([a, b])
        #expect(ledger.delivered(now: utc(10, 13)) == [AlertNotifications.identifier(for: a)])
        ledger = ledger.removing([AlertNotifications.identifier(for: b)])
        #expect(ledger.entries.count == 1)
        #expect(ledger.pruned(now: utc(12)).entries.isEmpty)
        #expect(ledger.pruned(now: utc(11)).entries.count == 1)
        let data = try? JSONEncoder().encode(ledger)
        #expect(data.flatMap { try? JSONDecoder().decode(NotificationLedger.self, from: $0) } == ledger)
    }
}
