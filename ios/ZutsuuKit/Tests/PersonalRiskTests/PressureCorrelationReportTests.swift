// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/PersonalRiskTests/PressureCorrelationReportTests.swift
// 相関レポートの最小サンプル数と集計を検証する。
// 「n=14 で相関と呼ばない」（設計書 §6.3）を固定するため。
// 関連: ../../Sources/PersonalRisk/PressureCorrelationReport.swift, docs/personalrisk-api.md §2
import Testing
import PersonalRisk
import RiskEngine

@Suite("気圧の相関レポート")
struct PressureCorrelationReportTests {
    private func observation(pressure: Int, baseline: Int = 0, bad: Bool) -> SymptomObservation {
        SymptomObservation(factors: RiskFactors(pressureChange: pressure, pressureBaseline: baseline,
                                                humidity: 0, precipitation: 0, temperature: 0),
                           wasBad: bad)
    }

    @Test("記録30日未満は出さず、残り日数を返す")
    func insufficientBelowMinimum() {
        let many = Array(repeating: observation(pressure: 3, bad: true), count: 200)
        #expect(PressureCorrelationReport.make(observations: many, recordedDays: 29)
                == .insufficient(remainingDays: 1))
        #expect(PressureCorrelationReport.make(observations: many, recordedDays: 0)
                == .insufficient(remainingDays: 30))
        #expect(PressureCorrelationReport.make(observations: many, recordedDays: -5)
                == .insufficient(remainingDays: 30))
    }

    @Test("気圧が動いた記録と穏やかな記録に分けて、つらいの件数を数える")
    func countsByPressureActivity() {
        let observations =
            Array(repeating: observation(pressure: 2, bad: true), count: 6)
            + Array(repeating: observation(pressure: 0, baseline: 1, bad: false), count: 4)
            + Array(repeating: observation(pressure: 0, bad: true), count: 2)
            + Array(repeating: observation(pressure: 0, bad: false), count: 8)
        guard case .ready(let summary) = PressureCorrelationReport.make(observations: observations,
                                                                          recordedDays: 30) else {
            Issue.record("30 日あれば出るはず"); return
        }
        #expect(summary.activeCount == 10 && summary.activeBad == 6)
        #expect(summary.calmCount == 10 && summary.calmBad == 2)
        #expect(summary.activeRate == 0.6)
        #expect(summary.calmRate == 0.2)
    }

    @Test("片側の記録がゼロなら割合はnil")
    func emptySideHasNoRate() {
        let onlyCalm = Array(repeating: observation(pressure: 0, bad: true), count: 3)
        guard case .ready(let summary) = PressureCorrelationReport.make(observations: onlyCalm,
                                                                          recordedDays: 40) else {
            Issue.record("出るはず"); return
        }
        #expect(summary.activeRate == nil)
        #expect(summary.calmRate == 1)
    }
}
