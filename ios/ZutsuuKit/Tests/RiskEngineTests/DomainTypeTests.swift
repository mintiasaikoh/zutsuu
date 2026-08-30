import Testing
import Foundation
import RiskEngine

@Suite("ドメイン型")
struct DomainTypeTests {
    @Test("リスクレベルは大小比較できる")
    func riskLevelIsComparable() {
        #expect(RiskLevel.calm < RiskLevel.danger)
        #expect(RiskLevel.allCases.count == 4)
    }

    @Test("リスクレベルの生値は 1〜4（TypeScript 実装との移植契約）")
    func riskLevelRawValues() {
        #expect(RiskLevel.allCases.map(\.rawValue) == [1, 2, 3, 4])
    }

    @Test("allCases は昇順に並んでいる")
    func riskLevelAllCasesAreAscending() {
        #expect(RiskLevel.allCases == RiskLevel.allCases.sorted())
    }

    @Test("リスク要因の合計は各要素の和")
    func riskFactorsTotal() {
        let f = RiskFactors(pressureChange: 2, pressureBaseline: 1,
                            humidity: 2, precipitation: 1, temperature: 2)
        #expect(f.total == 8)
    }

    @Test("気圧要因は変化量とその土地としての低さの和")
    func riskFactorsPressureIsSumOfItsParts() {
        let f = RiskFactors(pressureChange: 5, pressureBaseline: 3,
                            humidity: 0, precipitation: 0, temperature: 0)
        #expect(f.pressure == 8)
    }

    @Test("気圧変化量は時間窓ごとに保持される")
    func pressureChangesKeepsEachWindow() {
        let c = PressureChanges(oneHour: -1.5, threeHour: -4.0, sixHour: -6.5)
        #expect(c.oneHour == -1.5)
        #expect(c.threeHour == -4.0)
        #expect(c.sixHour == -6.5)
    }

    /// Task 10 の `AlertSchedulerTests` と Plan 3 のプレビューは、
    /// 予報を経由せず合成のリスク曲線を組み立てる。素の import で構築できることを固定する。
    @Test("リスク曲線はモジュール外から合成できる")
    func riskCurveIsSyntheticallyConstructible() {
        let assessment = RiskAssessment(
            level: .caution, score: 5,
            factors: RiskFactors(pressureChange: 5, pressureBaseline: 0,
                                 humidity: 0, precipitation: 0, temperature: 0))
        let risk = HourlyRisk(
            point: WeatherPoint(date: Date(timeIntervalSince1970: 0), pressure: 1013,
                                temperature: 20, humidity: 50,
                                precipitationChance: 0, precipitationAmount: 0),
            assessment: assessment,
            pressureChanges: PressureChanges(oneHour: -2, threeHour: -6, sixHour: -12))
        #expect(risk.assessment.level == .caution)
        #expect(risk.pressureChanges.sixHour == -12)
    }

    @Test("WeatherPointはモジュール外から構築できる")
    func weatherPointIsPubliclyConstructible() {
        let point = WeatherPoint(date: Date(timeIntervalSince1970: 0), pressure: 1013,
                                 temperature: 20, humidity: 60,
                                 precipitationChance: 30, precipitationAmount: 0)
        #expect(point.humidity == 60)
    }
}
