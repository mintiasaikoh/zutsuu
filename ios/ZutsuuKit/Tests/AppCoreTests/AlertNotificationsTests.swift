// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/AppCoreTests/AlertNotificationsTests.swift
// 通知の識別子の安定性と、種別ごとの文面・事実のみの制約を検証する。
// 再計算で予約が付け替わらないこと、睡眠中の影響を主張しないことを固定するため。
// 関連: ../../Sources/AppCore/AlertNotifications.swift, 設計書 §4「文面の制約」
import Testing
import Foundation
import AppCore
import RiskEngine

@Suite("通知の識別子と文面")
struct AlertNotificationsTests {

    private let target = utc(10, 14)
    private var risk: HourlyRisk {
        HourlyRisk(point: point(target, humidity: 85, chance: 80),
                   assessment: assessment(.caution, score: 6,
                                          factors: RiskFactors(pressureChange: 3, pressureBaseline: 0,
                                                               humidity: 2, precipitation: 2,
                                                               temperature: 0)),
                   pressureChanges: PressureChanges(oneHour: -1.2, threeHour: -6.4, sixHour: -5))
    }

    @Test("同じエピソードは再計算しても同じ識別子になる")
    func identifierIsStable() {
        let first = alert(kind: .advance, fire: utc(10, 12, 30), target: target)
        let recomputed = alert(kind: .advance, fire: utc(10, 12, 31), target: target, score: 9)
        #expect(AlertNotifications.identifier(for: first)
                == AlertNotifications.identifier(for: recomputed))
    }

    @Test("種別と入口時刻が違えば識別子も違う")
    func identifierDistinguishesKindAndTarget() {
        let advance = alert(kind: .advance, fire: utc(10, 12, 30), target: target)
        let wakeUp = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: target)
        let later = alert(kind: .advance, fire: utc(10, 13, 30), target: utc(10, 15))
        let ids = Set([advance, wakeUp, later].map(AlertNotifications.identifier(for:)))
        #expect(ids.count == 3)
    }

    @Test("事前警告は入口時刻とレベル、数値付きの要因を伝える")
    func advanceContent() {
        let alert = alert(kind: .advance, fire: utc(10, 12, 30), target: target,
                          factors: risk.assessment.factors)
        let content = AlertNotifications.content(for: alert, risks: [risk], calendar: utcCalendar)
        #expect(content.identifier == AlertNotifications.identifier(for: alert))
        #expect(content.fireDate == utc(10, 12, 30))
        #expect(content.kind == .advance)
        #expect(content.title == "14:00 頃から注意")
        #expect(content.body.contains("3時間で6hPa低下"))
        #expect(content.body.contains("湿度85%"))
        #expect(content.body.contains("降水確率80%"))
    }

    /// 「睡眠中に気圧が変化しました」は事実。「影響を受けました」は主張であり不可。
    @Test("起床時通知は睡眠中の影響を主張しない")
    func wakeUpContentStatesFactsOnly() {
        let alert = alert(kind: .wakeUp, fire: utc(10, 8, 30), target: utc(10, 3),
                          factors: risk.assessment.factors)
        let content = AlertNotifications.content(for: alert, risks: [], calendar: utcCalendar)
        #expect(content.title == "睡眠中に気圧が変化しました")
        #expect(content.body.hasPrefix("3:00 頃から注意"))
        for forbidden in ["影響", "予測", "診断"] {
            #expect(!content.title.contains(forbidden) && !content.body.contains(forbidden))
        }
    }

    @Test("入口が系列に無ければ数値なしの要因名で組み立てる")
    func fallsBackToFactorNames() {
        let alert = alert(kind: .advance, fire: utc(10, 12, 30), target: target,
                          factors: RiskFactors(pressureChange: 3, pressureBaseline: 2, humidity: 1,
                                               precipitation: 1, temperature: 1))
        let content = AlertNotifications.content(for: alert, risks: [], calendar: utcCalendar)
        #expect(content.body.contains("気圧の変化"))
        #expect(content.body.contains("この土地としては低い気圧"))
        #expect(content.body.contains("高い湿度"))
        #expect(content.body.contains("降水の可能性"))
        #expect(content.body.contains("気温の急な変化"))
    }

    @Test("時刻はカレンダーのタイムゾーンで表示される")
    func timeFollowsCalendar() {
        let alert = alert(kind: .advance, fire: utc(10, 12, 30), target: target)
        let content = AlertNotifications.content(for: alert, risks: [], calendar: tokyoCalendar)
        #expect(content.title == "23:00 頃から注意")
    }
}
