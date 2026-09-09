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
