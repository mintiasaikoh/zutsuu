import Testing
import Foundation
import RiskEngine

@Suite("通知予約時刻の算出")
struct AlertSchedulerTests {

    private let scheduler = AlertScheduler(calendar: utcCalendar)

    /// 既定の静穏時間（22:00〜08:30、日付をまたぐ）。
    private let night = QuietHours(start: 22, end: 8.5)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utcDate(year: 2026, month: 3, day: day, hour: hour, minute: minute)
    }

    // MARK: - 上がる瞬間を拾う

    /// 発火時刻・対象時刻・対象レベルの 3 つとも固定する。
    /// count だけの表明では fireDate と targetDate の取り違えや
    /// リードタイムの符号違いを見逃す。
    @Test("注意へ上がる90分前に予約される")
    func schedulesBeforeRiseToCaution() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution, .caution], startHour: 12)
        let alerts = scheduler.schedule(curve, quietHours: nil)
        #expect(alerts == [ScheduledAlert(fireDate: at(10, 12, 30),
                                          targetDate: at(10, 14),
                                          targetLevel: .caution)])
    }

    @Test("注意への上昇と危険への上昇はそれぞれ予約される")
    func schedulesEachRiseSeparately() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution, .danger, .danger], startHour: 12)
        let alerts = scheduler.schedule(curve, quietHours: nil)
        #expect(alerts == [
            ScheduledAlert(fireDate: at(10, 11, 30), targetDate: at(10, 13), targetLevel: .caution),
            ScheduledAlert(fireDate: at(10, 13, 30), targetDate: at(10, 15), targetLevel: .danger)
        ])
    }

    /// 最初から危険なら通知しない。すでに起きている事象であり、
    /// 画面に出ている情報を通知で繰り返しても価値がない。
    @Test("最初から危険な曲線では予約しない")
    func noAlertWhenAlreadyDanger() {
        let curve = makeRiskCurve(levels: [.danger, .danger, .danger, .danger], startHour: 12)
        #expect(scheduler.schedule(curve, quietHours: nil).isEmpty)
    }

    @Test("やや注意までしか上がらない曲線では予約しない")
    func noAlertBelowThreshold() {
        let curve = makeRiskCurve(levels: [.calm, .slight, .slight, .calm, .slight], startHour: 12)
        #expect(scheduler.schedule(curve, quietHours: nil).isEmpty)
    }

    @Test("下降では予約しない")
    func noAlertOnFall() {
        let curve = makeRiskCurve(levels: [.danger, .caution, .slight, .calm], startHour: 12)
        #expect(scheduler.schedule(curve, quietHours: nil).isEmpty)
    }

    /// 閾値をまたいで上下する曲線では上昇のたびに予約される（現行仕様）。
    /// 1 つの荒天イベントに対する通知の重複ではなく、
    /// 別々の上昇として扱われることをここで固定しておく。
    @Test("閾値をまたいで振動する曲線では上昇のたびに予約される")
    func oscillatingCurveSchedulesEachRise() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .calm, .caution, .calm, .caution],
                                  startHour: 12)
        let alerts = scheduler.schedule(curve, quietHours: nil)
        #expect(alerts.map(\.targetDate) == [at(10, 13), at(10, 15), at(10, 17)])
    }

    // MARK: - 静穏時間

    @Test("発火時刻が静穏時間に入る予約は行われない")
    func skipsAlertFiringInQuietHours() {
        // 09:00 に注意へ上がる → 発火は 07:30 で静穏時間内。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 7)
        #expect(scheduler.schedule(curve, quietHours: night).isEmpty)
        // 静穏時間がなければ予約される。上の空配列が別の理由でないことを示す。
        #expect(scheduler.schedule(curve, quietHours: nil).count == 1)
    }

    /// 判定対象が発火時刻であって対象時刻でないことを固定する。
    /// 23:00 のリスク上昇は対象時刻が静穏時間内だが、発火は 21:30 で外。
    /// `contains(targetDate)` に取り違えるとこのテストが落ちる。
    @Test("対象時刻が静穏時間内でも発火時刻が外なら予約する")
    func quietHoursAppliesToFireTimeNotTargetTime() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution], startHour: 22)
        let alerts = scheduler.schedule(curve, quietHours: night)
        #expect(alerts == [ScheduledAlert(fireDate: at(10, 21, 30),
                                          targetDate: at(10, 23),
                                          targetLevel: .caution)])
    }

    @Test("日付をまたぐ静穏時間の夜側が判定される")
    func quietHoursWrapEveningSide() {
        // 翌 00:00 に上昇 → 発火 22:30 で静穏時間内。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 22)
        #expect(scheduler.schedule(curve, quietHours: night).isEmpty)
        // 21:59 側は静穏時間の外。発火 21:30 は予約される。
        #expect(!night.contains(at(10, 21, 59), calendar: utcCalendar))
        #expect(night.contains(at(10, 22), calendar: utcCalendar))
    }

    @Test("日付をまたぐ静穏時間の朝側が判定される")
    func quietHoursWrapMorningSide() {
        // 03:00 に上昇 → 発火 01:30 で静穏時間内。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 1)
        #expect(scheduler.schedule(curve, quietHours: night).isEmpty)
        #expect(night.contains(at(10, 8, 29), calendar: utcCalendar))
        #expect(!night.contains(at(10, 8, 30), calendar: utcCalendar))
    }

    /// 終了時刻ちょうど（08:30）に発火する予約は行われる。
    /// 10:00 の上昇 → 発火 08:30。
    @Test("静穏時間の終了時刻ちょうどの発火は予約される")
    func quietHoursEndBoundaryIsScheduled() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 8)
        let alerts = scheduler.schedule(curve, quietHours: night)
        #expect(alerts == [ScheduledAlert(fireDate: at(10, 8, 30),
                                          targetDate: at(10, 10),
                                          targetLevel: .caution)])
    }

    /// 日付をまたがない静穏時間も扱える（昼寝など）。
    @Test("日付をまたがない静穏時間も判定される")
    func quietHoursWithoutWrap() {
        let siesta = QuietHours(start: 13, end: 15)
        #expect(!siesta.contains(at(10, 12, 59), calendar: utcCalendar))
        #expect(siesta.contains(at(10, 13), calendar: utcCalendar))
        #expect(siesta.contains(at(10, 14, 59), calendar: utcCalendar))
        #expect(!siesta.contains(at(10, 15), calendar: utcCalendar))
    }

    @Test("静穏時間がnilなら全て予約される")
    func nilQuietHoursSchedulesEverything() {
        // 発火が 01:30 と 07:30、いずれも既定の静穏時間なら落ちる並び。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution, .caution, .caution,
                                           .caution, .caution, .caution, .danger],
                                  startHour: 1)
        let alerts = scheduler.schedule(curve, quietHours: nil)
        #expect(alerts.map(\.fireDate) == [at(10, 1, 30), at(10, 7, 30)])
        #expect(scheduler.schedule(curve, quietHours: night).isEmpty)
    }

    // MARK: - 縮退した入力

    @Test("空の曲線では予約されず落ちない")
    func emptyCurve() {
        #expect(scheduler.schedule([], quietHours: night).isEmpty)
        #expect(scheduler.schedule([], quietHours: nil).isEmpty)
    }

    @Test("1点だけの曲線では予約されず落ちない")
    func singleElementCurve() {
        #expect(scheduler.schedule(makeRiskCurve(levels: [.danger]), quietHours: nil).isEmpty)
        #expect(scheduler.schedule(makeRiskCurve(levels: [.calm]), quietHours: nil).isEmpty)
    }

    // MARK: - 定数

    @Test("リードタイムと閾値の既定値")
    func constants() {
        #expect(AlertScheduler.leadTime == 90 * 60)
        #expect(AlertScheduler.threshold == .caution)
    }
}
