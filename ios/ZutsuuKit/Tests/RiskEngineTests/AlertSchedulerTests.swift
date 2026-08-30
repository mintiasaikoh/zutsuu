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

    /// 曲線（3/10）より十分手前の「今」。規則 1・5 が働かない基準時刻。
    private var early: Date { at(9, 12) }

    // MARK: - 規則 3: リードタイム

    @Test("注意へ上がる90分前に予約される")
    func schedulesBeforeRiseToCaution() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution, .caution], startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil) == [
            ScheduledAlert(fireDate: at(10, 12, 30), targetDate: at(10, 14),
                           assessment: curveAssessment(.caution))
        ])
    }

    @Test("やや注意までしか上がらない曲線では予約しない")
    func noAlertBelowThreshold() {
        let curve = makeRiskCurve(levels: [.calm, .slight, .slight, .calm, .slight], startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).isEmpty)
    }

    @Test("下降では予約しない")
    func noAlertOnFall() {
        let curve = makeRiskCurve(levels: [.danger, .caution, .slight, .calm], startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).isEmpty)
    }

    // MARK: - 規則 1: 過ぎた事象

    @Test("対象時刻が既に過ぎていれば予約しない")
    func dropsPastTarget() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 12)
        // 対象は 14:00。
        #expect(scheduler.schedule(curve, now: at(10, 14), quietHours: nil).isEmpty)
        #expect(scheduler.schedule(curve, now: at(10, 15), quietHours: nil).isEmpty)
        #expect(scheduler.schedule(curve, now: at(10, 13), quietHours: nil).count == 1)
    }

    // MARK: - 就寝中に到来するイベント

    /// 23:00 の上昇は発火 21:30 が静穏時間の外。就寝前に予告できる。
    /// 予防的な頭痛薬は早く飲むほど効くので、これは本アプリが送れる通知の中で
    /// 最も価値の高い部類にあたる。
    /// 「対象時刻が静穏時間内なら破棄」という規則を置くとこれが消える。
    @Test("就寝中に到来するイベントも起床中に事前通知する")
    func notifiesBeforeSleepForNightEvent() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution], startHour: 22)
        #expect(scheduler.schedule(curve, now: early, quietHours: night) == [
            ScheduledAlert(fireDate: at(10, 21, 30), targetDate: at(10, 23),
                           assessment: curveAssessment(.caution))
        ])
    }

    /// 深夜のイベントは、繰り下げ先（明けの 08:30）が対象時刻を追い越すので
    /// 規則 5 で落ちる。破棄の判断は専用の規則ではなく繰り下げの結果から出る。
    @Test("事前に知らせる術がない深夜のイベントは予約しない")
    func dropsMidnightEventWithNoWayToWarnAhead() {
        // 03:00 に注意へ上がる。素の発火 01:30 は静穏時間内。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 1)
        #expect(scheduler.schedule(curve, now: early, quietHours: night).isEmpty)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).count == 1)
    }

    // MARK: - 規則 4: 静穏時間に掛かる発火は繰り下げる（P1 の修正）

    /// 09:00 の上昇は素の発火が 07:30 で静穏時間内。
    /// 破棄せず 08:30（明け）へ繰り下げ、30 分のリードで届ける。
    @Test("発火が静穏時間に掛かる場合は明けまで繰り下げる")
    func shiftsFireTimeToEndOfQuietHours() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 7)
        #expect(scheduler.schedule(curve, now: early, quietHours: night) == [
            ScheduledAlert(fireDate: at(10, 8, 30), targetDate: at(10, 9),
                           assessment: curveAssessment(.caution))
        ])
        // 静穏時間が無ければ本来のリードタイムどおり 07:30。
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).first?.fireDate
                == at(10, 7, 30))
    }

    @Test("静穏時間の終了時刻ちょうどの発火はそのまま予約される")
    func quietHoursEndBoundaryIsScheduled() {
        // 10:00 の上昇 → 発火 08:30。境界は静穏時間に含まない。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 8)
        #expect(scheduler.schedule(curve, now: early, quietHours: night).first?.fireDate
                == at(10, 8, 30))
    }

    /// 繰り下げ先が翌日になる場合。既定の 22:00〜08:30 では
    /// 発火が夜側に落ちる上昇は対象時刻も静穏時間内になり規則 2 で消えるため、
    /// 明けが日付をまたぐ短い設定（22:00〜00:30）で検証する。
    /// 「発火時刻と同じ日の end」を組み立てる実装だと 24 時間前を指してしまう。
    @Test("日付をまたいで繰り下げる")
    func shiftAcrossMidnight() {
        let lateNight = QuietHours(start: 22, end: 0.5)
        // 23:00, 00:00, 01:00。対象は 3/11 01:00、素の発火は 3/10 23:30。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 23)
        #expect(scheduler.schedule(curve, now: early, quietHours: lateNight) == [
            ScheduledAlert(fireDate: at(11, 0, 30), targetDate: at(11, 1),
                           assessment: curveAssessment(.caution))
        ])
    }

    /// 夏時間で存在しない時刻へ繰り下げる場合。
    /// America/New_York の 2026-03-08 は 02:00 から 03:00 へ飛ぶ。
    /// 静穏時間の明けを 02:30 に設定すると、その日だけ明けの壁時計時刻が存在しない。
    /// カレンダー演算が直後の実在時刻（03:00 EDT）へ送ることを固定する。
    @Test("夏時間で存在しない明けの時刻でも繰り下げられる")
    func shiftAcrossSpringForward() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // 3/8 01:00 EST から 1 時間刻み。2 点先は 04:00 EDT。
        let base = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1))!
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 0, day: base)
        let alerts = AlertScheduler(calendar: newYork)
            .schedule(curve, now: base.addingTimeInterval(-86_400),
                      quietHours: QuietHours(start: 22, end: 2.5))
        let expected = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3))!
        #expect(alerts.map(\.fireDate) == [expected])
        #expect(alerts.map(\.targetDate) == [base.addingTimeInterval(2 * 3600)])
    }

    // MARK: - 規則 5: 発火時刻が過ぎている（P2 の修正）

    /// 予報の開始直後に上がる場合、素の発火時刻は予報開始より前になる。
    /// 過去の時刻を返すとアプリ層で予約できない（トリガの間隔が正でない）。
    @Test("発火時刻が過ぎていれば現在時刻の直後に繰り上げる")
    func clampsPastFireTimeToNow() throws {
        let now = at(10, 12)
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution], startHour: 12)
        let alerts = scheduler.schedule(curve, now: now, quietHours: nil)
        #expect(alerts == [
            ScheduledAlert(fireDate: at(10, 12, 1), targetDate: at(10, 13),
                           assessment: curveAssessment(.caution))
        ])
        let alert = try #require(alerts.first)
        #expect(alert.fireDate > now)
        #expect(alert.fireDate == now.addingTimeInterval(AlertScheduler.grace))
    }

    /// 繰り上げ先が静穏時間内に落ちてはいけない。
    /// 静穏時間がリードタイムより短い設定（13:00〜13:30 の昼寝）では、
    /// 繰り上げてから繰り下げないと静穏時間の最中に鳴る。
    @Test("繰り上げた発火時刻も静穏時間の外に置かれる")
    func clampedFireTimeStaysOutsideQuietHours() throws {
        let siesta = QuietHours(start: 13, end: 13.5)
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 12)
        let alerts = scheduler.schedule(curve, now: at(10, 13, 10), quietHours: siesta)
        #expect(alerts.map(\.fireDate) == [at(10, 13, 30)])
        let alert = try #require(alerts.first)
        #expect(!siesta.contains(alert.fireDate, calendar: utcCalendar))
    }

    // MARK: - 規則 6: リードタイムが残らない

    @Test("繰り上げた発火が対象時刻を越える場合は予約しない")
    func dropsWhenNoLeadTimeRemainsAfterClamp() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution], startHour: 12)
        // 対象は 13:00。now + grace が 13:00 以降になると価値がない。
        #expect(scheduler.schedule(curve, now: at(10, 13).addingTimeInterval(-30),
                                   quietHours: nil).isEmpty)
        #expect(scheduler.schedule(curve, now: at(10, 13).addingTimeInterval(-120),
                                   quietHours: nil).map(\.fireDate) == [at(10, 12, 59)])
    }

    @Test("繰り下げた発火が対象時刻を越える場合は予約しない")
    func dropsWhenNoLeadTimeRemainsAfterShift() {
        // 対象 09:00。明けが 09:00 なら繰り下げ先が対象時刻に並ぶので予約しない。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 7)
        #expect(scheduler.schedule(curve, now: early,
                                   quietHours: QuietHours(start: 22, end: 9)).isEmpty)
        // 明けが 08:45 なら 15 分のリードが残るので予約する。
        #expect(scheduler.schedule(curve, now: early,
                                   quietHours: QuietHours(start: 22, end: 8.75))
                    .map(\.fireDate) == [at(10, 8, 45)])
    }

    // MARK: - エピソード集約（P3 の修正）

    /// 1 回の荒天で連投しない。入口は最初の閾値超え、レベルは区間中の最高。
    @Test("段階的に悪化する曲線は1件にまとまる")
    func coalescesGradualEscalation() {
        let curve = makeRiskCurve(levels: [.calm, .slight, .caution, .danger, .danger],
                                  startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil) == [
            ScheduledAlert(fireDate: at(10, 12, 30), targetDate: at(10, 14),
                           assessment: curveAssessment(.danger))
        ])
    }

    /// 対象時刻は入口（13:00）、判定はピーク（危険）。
    /// 入口の判定を抱えると `assessment` が注意になり、
    /// ピークの時刻を対象にすると `targetDate` が 14:00 になる。
    @Test("入口の時刻とピークの判定を組み合わせて持つ")
    func carriesOnsetDateAndPeakAssessment() throws {
        let curve = makeRiskCurve(levels: [.calm, .caution, .danger, .caution], startHour: 12)
        let alerts = scheduler.schedule(curve, now: early, quietHours: nil)
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.targetDate == at(10, 13))
        #expect(alert.assessment == curveAssessment(.danger))
        #expect(alert.assessment.score == 7)
    }

    @Test("閾値未満に落ちてから再び上がれば別の予約になる")
    func newEpisodeAfterDroppingBelowThreshold() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .calm, .danger, .calm, .caution],
                                  startHour: 12)
        let alerts = scheduler.schedule(curve, now: early, quietHours: nil)
        #expect(alerts.map(\.targetDate) == [at(10, 13), at(10, 15), at(10, 17)])
        #expect(alerts.map(\.targetLevel) == [.caution, .danger, .caution])
    }

    /// 最初から危険なら通知しない。すでに起きている事象であり、
    /// 画面に出ている情報を通知で繰り返しても価値がない。
    @Test("最初から危険な曲線では予約しない")
    func noAlertWhenAlreadyDanger() {
        let curve = makeRiskCurve(levels: [.danger, .danger, .danger, .danger], startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).isEmpty)
    }

    /// 先頭から続く区間は飛ばすが、その後の上昇は拾う。
    @Test("先頭から続く区間の後の上昇は予約される")
    func skipsLeadingEpisodeButKeepsLaterOne() {
        let curve = makeRiskCurve(levels: [.danger, .danger, .calm, .caution, .caution],
                                  startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).map(\.targetDate)
                == [at(10, 15)])
    }

    // MARK: - 静穏時間の判定

    @Test("日付をまたぐ静穏時間の境界")
    func quietHoursWrapBoundaries() {
        #expect(!night.contains(at(10, 21, 59), calendar: utcCalendar))
        #expect(night.contains(at(10, 22), calendar: utcCalendar))
        #expect(night.contains(at(10, 3), calendar: utcCalendar))
        #expect(night.contains(at(10, 8, 29), calendar: utcCalendar))
        #expect(!night.contains(at(10, 8, 30), calendar: utcCalendar))
    }

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
        // 対象 03:00 と 09:00。既定の静穏時間なら前者は規則 2、後者は繰り下げ対象。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution, .calm, .calm,
                                           .calm, .calm, .calm, .caution],
                                  startHour: 1)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).map(\.fireDate)
                == [at(10, 1, 30), at(10, 7, 30)])
        #expect(scheduler.schedule(curve, now: early, quietHours: night).map(\.fireDate)
                == [at(10, 8, 30)])
    }

    // MARK: - 静穏時間の値の検証（P4）

    /// 幅ゼロは「静穏時間なし」。無効化の手段としてユーザーが取り得る設定なので
    /// 実装バグ扱いにはしない。
    @Test("開始と終了が同じなら静穏時間なしとして扱う")
    func zeroWidthQuietHoursIsDisabled() {
        let disabled = QuietHours(start: 8.5, end: 8.5)
        #expect(!disabled.isEnabled)
        #expect(!disabled.contains(at(10, 3), calendar: utcCalendar))
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 1)
        #expect(scheduler.schedule(curve, now: early, quietHours: disabled).map(\.fireDate)
                == [at(10, 1, 30)])
    }

    // 非有限値・範囲外は設定の読み違えによる実装バグ。デバッグでは停止させ、
    // リリースでは「静穏時間なし」に倒す。契約が構成ごとに異なるのでテストも分ける。
    #if DEBUG
    @Test("非有限の静穏時間はデバッグビルドで検出される")
    func nonFiniteQuietHoursIsCaughtInDebug() async {
        await #expect(processExitsWith: .failure) {
            _ = QuietHours(start: .nan, end: 8.5).isEnabled
        }
    }

    /// `contains` 経由でも検出されること。`isEnabled` を直接呼ぶ経路だけを
    /// 塞いでも、判定に使われるのは `contains` のほう。
    @Test("範囲外の静穏時間はデバッグビルドで検出される")
    func outOfRangeQuietHoursIsCaughtInDebug() async {
        await #expect(processExitsWith: .failure) {
            _ = QuietHours(start: 24, end: 8.5).contains(Date(), calendar: utcCalendar)
        }
    }
    #else
    @Test("不正な静穏時間はリリースビルドで無効として扱われる")
    func invalidQuietHoursIsDisabledInRelease() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 1)
        for invalid in [QuietHours(start: .nan, end: 8.5),
                        QuietHours(start: 22, end: .infinity),
                        QuietHours(start: 24, end: 8.5),
                        QuietHours(start: -1, end: 8.5)] {
            #expect(!invalid.isEnabled)
            #expect(!invalid.contains(at(10, 3), calendar: utcCalendar))
            #expect(scheduler.schedule(curve, now: early, quietHours: invalid).count == 1)
        }
    }
    #endif

    // MARK: - 縮退した入力

    @Test("空の曲線では予約されず落ちない")
    func emptyCurve() {
        #expect(scheduler.schedule([], now: early, quietHours: night).isEmpty)
        #expect(scheduler.schedule([], now: early, quietHours: nil).isEmpty)
    }

    @Test("1点だけの曲線では予約されず落ちない")
    func singleElementCurve() {
        #expect(scheduler.schedule(makeRiskCurve(levels: [.danger]),
                                   now: early, quietHours: nil).isEmpty)
        #expect(scheduler.schedule(makeRiskCurve(levels: [.calm]),
                                   now: early, quietHours: nil).isEmpty)
    }

    // MARK: - 定数

    @Test("リードタイム・閾値・猶予の既定値")
    func constants() {
        #expect(AlertScheduler.leadTime == 90 * 60)
        #expect(AlertScheduler.threshold == .caution)
        #expect(AlertScheduler.grace == 60)
    }
}
