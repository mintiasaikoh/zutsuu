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

    /// 曲線（3/10）より十分手前の「今」。規則 1・3 が働かない基準時刻。
    private var early: Date { at(9, 12) }

    // MARK: - 規則 2: リードタイム

    @Test("注意へ上がる90分前に予約される")
    func schedulesBeforeRiseToCaution() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution, .caution], startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil) == [
            ScheduledAlert(fireDate: at(10, 12, 30), targetDate: at(10, 14),
                           assessment: curveAssessment(.caution), kind: .advance)
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
                           assessment: curveAssessment(.caution), kind: .advance)
        ])
    }

    /// 深夜のイベントは、繰り下げ先（明けの 08:30）が対象時刻を追い越す。
    /// 事前には知らせられないが、破棄せず起床時通知にする。
    /// このアプリの通知が伝えるのは主に「薬を飲む時刻」であり、
    /// それは事象の開始後でも実行できる行動だから。
    @Test("事前に知らせる術がない深夜のイベントは起床時通知になる")
    func convertsMidnightEventToWakeUpAlert() throws {
        // 03:00 に注意へ上がる。素の発火 01:30 は静穏時間内。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 1)
        #expect(scheduler.schedule(curve, now: early, quietHours: night) == [
            ScheduledAlert(fireDate: at(10, 8, 30), targetDate: at(10, 3),
                           assessment: curveAssessment(.caution), kind: .wakeUp)
        ])
        // 静穏時間が無ければ本来のリードタイムどおり事前通知。件数も 1 のまま。
        let free = scheduler.schedule(curve, now: early, quietHours: nil)
        #expect(free.count == 1)
        let alert = try #require(free.first)
        #expect(alert.fireDate == at(10, 1, 30))
        #expect(alert.kind == .advance)
    }

    /// 静穏時間の入口ぎりぎり（00:30）に到来するイベントも同じ扱い。
    /// 素の発火 23:00 は静穏時間内なので繰り下がる。
    @Test("静穏時間の入口直後のイベントも起床時通知になる")
    func convertsEarlyNightEventToWakeUpAlert() {
        // 22:30, 23:30, 00:30。対象は 3/11 00:30、素の発火は 3/10 23:00。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution],
                                  startHour: 0,
                                  day: at(10, 22, 30))
        #expect(scheduler.schedule(curve, now: early, quietHours: night) == [
            ScheduledAlert(fireDate: at(11, 8, 30), targetDate: at(11, 0, 30),
                           assessment: curveAssessment(.caution), kind: .wakeUp)
        ])
    }

    /// 起床時通知では `fireDate` が `targetDate` より後になる。
    /// 事前警告と前後関係が反転するのはこの型の最も踏みやすい罠で、
    /// アプリ層は `kind` を見て文面を分けなければならない。
    @Test("起床時通知では発火時刻が対象時刻より後になる")
    func wakeUpAlertFiresAfterTarget() throws {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 1)
        let alert = try #require(scheduler.schedule(curve, now: early,
                                                    quietHours: night).first)
        #expect(alert.kind == .wakeUp)
        #expect(alert.fireDate > alert.targetDate)
        // 静穏時間の外であることは起床時通知でも保たれる。
        #expect(!night.contains(alert.fireDate, calendar: utcCalendar))
        // 過去には鳴らせない。予約可能であることは変わらない。
        #expect(alert.fireDate > early)
    }

    /// 繰り上げ（規則 3）由来の追い越しは従来どおり破棄する。
    /// こちらは就寝中に過ぎたのではなく、本当に直前に迫った事象であり、
    /// 明けまで繰り下げる話にはならない（そもそも静穏時間に掛かっていない）。
    @Test("繰り上げ由来の追い越しは起床時通知にせず破棄する")
    func nowClampOvershootIsStillDropped() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution], startHour: 12)
        // 対象 13:00 の 30 秒前。now + grace = 13:00:30 で対象を追い越す。
        #expect(scheduler.schedule(curve, now: at(10, 13).addingTimeInterval(-30),
                                   quietHours: nil).isEmpty)
        // 静穏時間があっても同じ。繰り下げの手前で落ちる。
        #expect(scheduler.schedule(curve, now: at(10, 13).addingTimeInterval(-30),
                                   quietHours: night).isEmpty)
    }

    // MARK: - 規則 5: 静穏時間に掛かる発火は繰り下げる（P1 の修正）

    /// 09:00 の上昇は素の発火が 07:30 で静穏時間内。
    /// 破棄せず 08:30（明け）へ繰り下げ、30 分のリードで届ける。
    @Test("発火が静穏時間に掛かる場合は明けまで繰り下げる")
    func shiftsFireTimeToEndOfQuietHours() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 7)
        #expect(scheduler.schedule(curve, now: early, quietHours: night) == [
            ScheduledAlert(fireDate: at(10, 8, 30), targetDate: at(10, 9),
                           assessment: curveAssessment(.caution), kind: .advance)
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
                           assessment: curveAssessment(.caution), kind: .advance)
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

    // MARK: - 規則 3: 発火時刻が過ぎている（P2 の修正）

    /// 予報の開始直後に上がる場合、素の発火時刻は予報開始より前になる。
    /// 過去の時刻を返すとアプリ層で予約できない（トリガの間隔が正でない）。
    @Test("発火時刻が過ぎていれば現在時刻の直後に繰り上げる")
    func clampsPastFireTimeToNow() throws {
        let now = at(10, 12)
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution], startHour: 12)
        let alerts = scheduler.schedule(curve, now: now, quietHours: nil)
        #expect(alerts == [
            ScheduledAlert(fireDate: at(10, 12, 1), targetDate: at(10, 13),
                           assessment: curveAssessment(.caution), kind: .advance)
        ])
        let alert = try #require(alerts.first)
        #expect(alert.fireDate > now)
        #expect(alert.fireDate == now.addingTimeInterval(AlertScheduler.grace))
    }

    /// 素の発火時刻が `now` ちょうどの境界。
    /// `ScheduledAlert` は「アプリ層が時刻を再検査しなくてよい」と約束しており、
    /// その約束はこの比較が等号を含むことに乗っている。等号を落とすと
    /// `fireDate == now` の予約が返り、`UNTimeIntervalNotificationTrigger` が
    /// 間隔 0 で例外を投げる。
    @Test("素の発火時刻が現在時刻ちょうどでも繰り上げる")
    func clampsFireTimeAtExactlyNow() throws {
        let now = at(10, 11, 30)    // 対象 13:00 のリードタイム 90 分ちょうど手前
        let curve = makeRiskCurve(levels: [.calm, .caution], startHour: 12)
        let alert = try #require(scheduler.schedule(curve, now: now, quietHours: nil).first)
        #expect(alert.fireDate > now)
        #expect(alert.fireDate == now.addingTimeInterval(AlertScheduler.grace))
    }

    /// 曲線に対する `now` の位置を 1 分刻みで動かし、返る予約が常に未来を指すことを見る。
    /// 個別の境界ではなく不変条件として固定する。
    @Test("どの現在時刻に対しても発火時刻は現在より後になる")
    func fireDateIsAlwaysAfterNow() {
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution, .caution,
                                           .calm, .danger, .danger],
                                  startHour: 12)
        let configurations: [QuietHours?] = [nil, night]
        for quietHours in configurations {
            var scheduled = 0
            for minute in stride(from: -120, through: 420, by: 1) {
                let now = at(10, 12).addingTimeInterval(TimeInterval(minute) * 60)
                for alert in scheduler.schedule(curve, now: now, quietHours: quietHours) {
                    scheduled += 1
                    #expect(alert.fireDate > now,
                            "now=\(now) fireDate=\(alert.fireDate)")
                }
            }
            // 1 件も返らなければ上の表明は空振り。件数そのものを下から押さえる。
            #expect(scheduled > 300)
        }
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

    // MARK: - 規則 5a・5b: リードタイムが残らない

    @Test("繰り上げた発火が対象時刻を越える場合は予約しない")
    func dropsWhenNoLeadTimeRemainsAfterClamp() {
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution], startHour: 12)
        // 対象は 13:00。now + grace が 13:00 以降になると価値がない。
        #expect(scheduler.schedule(curve, now: at(10, 13).addingTimeInterval(-30),
                                   quietHours: nil).isEmpty)
        #expect(scheduler.schedule(curve, now: at(10, 13).addingTimeInterval(-120),
                                   quietHours: nil).map(\.fireDate) == [at(10, 12, 59)])
    }

    /// 繰り下げ先が対象時刻に**並ぶ**境界。リードは 0 分。
    /// 事前警告としては成立しないので起床時通知に倒す。
    /// `.advance` の約束（`fireDate < targetDate`）を満たさない以上、
    /// ここを `.advance` と名乗らせるとアプリ層の分岐が壊れる。
    @Test("繰り下げた発火が対象時刻に並ぶ場合は起床時通知になる")
    func shiftOntoTargetIsWakeUp() throws {
        // 対象 09:00。明けが 09:00 なら繰り下げ先が対象時刻に並ぶ。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 7)
        let boundary = scheduler.schedule(curve, now: early,
                                          quietHours: QuietHours(start: 22, end: 9))
        #expect(boundary.count == 1)
        let alert = try #require(boundary.first)
        #expect(alert.fireDate == at(10, 9))
        #expect(alert.targetDate == at(10, 9))
        #expect(alert.kind == .wakeUp)

        // 明けが 08:45 なら 15 分のリードが残るので事前警告のまま。
        let remaining = scheduler.schedule(curve, now: early,
                                           quietHours: QuietHours(start: 22, end: 8.75))
        #expect(remaining.count == 1)
        let ahead = try #require(remaining.first)
        #expect(ahead.fireDate == at(10, 8, 45))
        #expect(ahead.kind == .advance)
    }

    // MARK: - エピソード集約（P3 の修正）

    /// 1 回の荒天で連投しない。入口は最初の閾値超え、レベルは区間中の最高。
    @Test("段階的に悪化する曲線は1件にまとまる")
    func coalescesGradualEscalation() {
        let curve = makeRiskCurve(levels: [.calm, .slight, .caution, .danger, .danger],
                                  startHour: 12)
        #expect(scheduler.schedule(curve, now: early, quietHours: nil) == [
            ScheduledAlert(fireDate: at(10, 12, 30), targetDate: at(10, 14),
                           assessment: curveAssessment(.danger), kind: .advance)
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

    /// 同じ「危険」の中でもスコアは動く。通知本文が名乗る内訳は、
    /// 最初に危険へ到達した時点ではなく、区間中で最も強い時点のもの。
    /// 7pt → 15pt → 8pt の停滞で 7pt を選ぶと、事象全体で最も弱い内訳を読み上げる。
    @Test("エピソード中で最もスコアの高い時点の判定を持つ")
    func carriesHighestScoringAssessment() throws {
        let onset = curveFactors(pressureChange: 7)                             // 7pt
        let peak = curveFactors(pressureChange: 8, pressureBaseline: 3,
                                humidity: 3, precipitation: 1)                  // 15pt
        let subsiding = curveFactors(pressureChange: 4, pressureBaseline: 1,
                                     humidity: 2, temperature: 1)               // 8pt
        let curve = makeRiskCurve(levels: [.calm, .danger, .danger, .danger],
                                  factors: [curveFactors(), onset, peak, subsiding],
                                  startHour: 12)
        let alerts = scheduler.schedule(curve, now: early, quietHours: nil)
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.assessment.factors == peak)
        #expect(alert.assessment.score == 15)
        // レベルは最高スコアの時点から導出しても最高レベルのまま。
        #expect(alert.targetLevel == .danger)
        // 対象時刻はピークの位置（14:00）ではなくエピソードの入口。
        #expect(alert.targetDate == at(10, 13))
        #expect(alert.fireDate == at(10, 11, 30))
    }

    /// 同点なら早いほうを残す。後勝ちにすると、同じ強さの停滞で
    /// 通知が抱える内訳が区間の長さに左右される。
    @Test("同点のスコアでは最も早い時点の判定を持つ")
    func keepsEarliestAssessmentOnTie() throws {
        let pressureDriven = curveFactors(pressureChange: 7)                    // 7pt
        let humidityDriven = curveFactors(pressureChange: 4, humidity: 3)       // 7pt
        let curve = makeRiskCurve(levels: [.calm, .danger, .danger],
                                  factors: [curveFactors(), pressureDriven, humidityDriven],
                                  startHour: 12)
        let alert = try #require(scheduler.schedule(curve, now: early, quietHours: nil).first)
        #expect(alert.assessment.factors == pressureDriven)
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

    // MARK: - 一晩の起床時通知の集約

    /// 一晩に乱れが 3 回あっても、明けに鳴る通知は 1 件。
    /// 起床と同時に通知が 3 件並ぶのは、直そうとした問題より悪い体験になる。
    ///
    /// `targetDate` は最も早い入口（00:00）、`assessment` は最も強い時点（02:00 の危険）。
    /// 別々の時点を指す組み合わせであることがこのテストの主眼で、
    /// 「その夜で最も強かった内訳」と「乱れが始まった時刻」をそれぞれ伝える。
    @Test("一晩に複数のエピソードがあっても起床時通知は1件にまとまる")
    func coalescesNightEpisodesIntoSingleWakeUpAlert() throws {
        // 3/10 23:00 から 1 時間刻み。入口は 00:00・02:00・04:00 の 3 つ。
        let curve = makeRiskCurve(levels: [.calm, .caution, .calm, .danger,
                                           .calm, .caution, .calm],
                                  startHour: 23)
        let alerts = scheduler.schedule(curve, now: early, quietHours: night)
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.kind == .wakeUp)
        #expect(alert.fireDate == at(11, 8, 30))
        // 最も早い入口。ピークの時点（02:00）でも最後の入口（04:00）でもない。
        #expect(alert.targetDate == at(11, 0))
        // 束ねた中で最もスコアの高い判定。最も早いエピソードの注意ではない。
        #expect(alert.assessment == curveAssessment(.danger))
        #expect(alert.targetLevel == .danger)

        // 静穏時間が無ければ 3 件のまま。束ねているのは起床時通知だけ。
        #expect(scheduler.schedule(curve, now: early, quietHours: nil).count == 3)
    }

    /// スコアが同点なら最も早いエピソードの内訳を残す。
    /// エピソード内の同点規則をエピソード間へそのまま延長している。
    @Test("同点のエピソード同士では最も早い内訳を残す")
    func coalescedWakeUpKeepsEarliestAssessmentOnTie() throws {
        let pressureDriven = curveFactors(pressureChange: 7)                    // 7pt
        let humidityDriven = curveFactors(pressureChange: 4, humidity: 3)       // 7pt
        // 3/10 23:00 から。入口は 00:00 と 02:00。
        let curve = makeRiskCurve(levels: [.calm, .danger, .calm, .danger, .calm],
                                  factors: [curveFactors(), pressureDriven,
                                            curveFactors(), humidityDriven, curveFactors()],
                                  startHour: 23)
        let alert = try #require(scheduler.schedule(curve, now: early,
                                                    quietHours: night).first)
        #expect(alert.assessment.factors == pressureDriven)
        #expect(alert.targetDate == at(11, 0))
    }

    /// 別々の夜は別々の通知。束ねる単位は「同じ明けへ繰り下がったもの」。
    @Test("夜が違えば起床時通知は別々に残る")
    func doesNotCoalesceAcrossDifferentNights() {
        // 3/10 23:00 から 1 時間刻みで 27 点。入口は 3/11 00:00 と 3/12 00:00。
        var levels = [RiskLevel](repeating: .calm, count: 27)
        levels[1] = .caution
        levels[25] = .danger
        let alerts = scheduler.schedule(makeRiskCurve(levels: levels, startHour: 23),
                                        now: early, quietHours: night)
        #expect(alerts.map(\.kind) == [.wakeUp, .wakeUp])
        #expect(alerts.map(\.fireDate) == [at(11, 8, 30), at(12, 8, 30)])
        #expect(alerts.map(\.targetDate) == [at(11, 0), at(12, 0)])
    }

    // MARK: - 静穏時間を 30 分刻みで一周する

    /// 既定の静穏時間（22:00〜08:30）に対し、入口を 30 分刻みで 48 通り動かす。
    /// 個別の時刻ではなく「無通知の穴が残っていないこと」を固定するためのテスト。
    ///
    /// 変更前は 19/48（00:00〜08:30 の 18 枠と 23:30）が破棄されていた。
    /// 時計の 9 時間ぶんが無通知だったことになる。変更後はその 19 枠が
    /// そのまま起床時通知になり、破棄はゼロになる。
    @Test("30分刻みの全48通りの入口で通知が失われない")
    func everyOnsetSlotProducesAnAlert() {
        var kinds: [AlertKind] = []
        for slot in 0..<48 {
            let onset = at(10, 0).addingTimeInterval(TimeInterval(slot) * 1800)
            let curve = makeRiskCurve(levels: [.calm, .caution, .caution],
                                      startHour: 0,
                                      day: onset.addingTimeInterval(-3600))
            let alerts = scheduler.schedule(curve, now: early, quietHours: night)
            #expect(alerts.count == 1, "入口 \(onset) で予約が \(alerts.count) 件")
            guard let alert = alerts.first else { continue }
            #expect(alert.targetDate == onset)
            #expect(!night.contains(alert.fireDate, calendar: utcCalendar))
            kinds.append(alert.kind)
        }
        // 件数を先に押さえないと、以下の内訳は空配列でも成立してしまう。
        #expect(kinds.count == 48)
        // 起床時通知になるのは 00:00〜08:30 の 18 枠と 23:30 の計 19 枠。
        // 変更前に破棄されていた集合とちょうど一致する。
        let wakeUpSlots = Set(kinds.indices.filter { kinds[$0] == .wakeUp })
        #expect(wakeUpSlots == Set(0...17).union([47]))
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

    @Test("静穏時間がnilなら全て本来のリードタイムで予約される")
    func nilQuietHoursSchedulesEverything() {
        // 対象 03:00 と 09:00。既定の静穏時間なら前者は起床時通知、後者は繰り下げ。
        let curve = makeRiskCurve(levels: [.calm, .calm, .caution, .calm, .calm,
                                           .calm, .calm, .calm, .caution],
                                  startHour: 1)
        let free = scheduler.schedule(curve, now: early, quietHours: nil)
        #expect(free.map(\.fireDate) == [at(10, 1, 30), at(10, 7, 30)])
        #expect(free.map(\.kind) == [.advance, .advance])

        // 夜間の乱れ（起床時通知）と朝の上昇（事前警告）は別々に残る。
        // 発火時刻は同じ 08:30 でも伝える内容が違うため束ねない。
        let quiet = scheduler.schedule(curve, now: early, quietHours: night)
        #expect(quiet.map(\.fireDate) == [at(10, 8, 30), at(10, 8, 30)])
        #expect(quiet.map(\.targetDate) == [at(10, 3), at(10, 9)])
        #expect(quiet.map(\.kind) == [.wakeUp, .advance])
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

// MARK: - レビュー R11: 個人化後のレベルはスコアに対して単調でない

@Suite("ピークの選び方")
struct AlertSchedulerPeakTests {
    private let scheduler = AlertScheduler(calendar: utcCalendar)
    private let early = utcDate(year: 2026, month: 3, day: 10, hour: 8)

    /// 安心 → 危険（6pt）→ 注意（7pt）の区間で、最高レベルは「危険」。
    /// スコアだけで選ぶと 7pt の「注意」を代表にしてしまう。
    @Test("レベルが高い時点を、スコアが高い時点より優先する")
    func levelBeatsScore() throws {
        let dangerLow = RiskFactors(pressureChange: 3, pressureBaseline: 0, humidity: 3,
                                    precipitation: 0, temperature: 0)   // 6pt
        let cautionHigh = RiskFactors(pressureChange: 3, pressureBaseline: 0, humidity: 0,
                                      precipitation: 2, temperature: 2)  // 7pt
        let curve = makeRiskCurve(levels: [.calm, .danger, .caution],
                                  factors: [curveFactors(), dangerLow, cautionHigh],
                                  startHour: 12)
        let alert = try #require(scheduler.schedule(curve, now: early, quietHours: nil).first)
        #expect(alert.targetLevel == .danger)
        #expect(alert.assessment.factors == dangerLow)
    }

    @Test("同じレベルならスコアの高い時点、同点なら早い時点")
    func scoreBreaksTies() throws {
        let a = RiskFactors(pressureChange: 4, pressureBaseline: 0, humidity: 1, precipitation: 0, temperature: 0)
        let b = RiskFactors(pressureChange: 4, pressureBaseline: 1, humidity: 1, precipitation: 0, temperature: 0)
        let curve = makeRiskCurve(levels: [.calm, .caution, .caution],
                                  factors: [curveFactors(), a, b], startHour: 12)
        let alert = try #require(scheduler.schedule(curve, now: early, quietHours: nil).first)
        #expect(alert.assessment.factors == b)
    }
}
