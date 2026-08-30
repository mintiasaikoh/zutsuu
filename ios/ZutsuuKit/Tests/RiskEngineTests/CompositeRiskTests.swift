import Testing
@testable import RiskEngine

@Suite("複合リスク")
struct CompositeRiskTests {

    @Test("スコアからリスクレベルへの変換", arguments: [
        (0, RiskLevel.calm), (1, .slight), (3, .slight),
        (4, .caution), (6, .caution), (7, .danger), (13, .danger)
    ])
    func levelConversion(score: Int, expected: RiskLevel) {
        #expect(riskLevel(forScore: score) == expected)
    }

    @Test("複合スコアは各要因の和になる")
    func sumsFactors() {
        let result = compositeRisk(
            pressureChanges: PressureChanges(oneHour: -4, threeHour: -8, sixHour: -10),
            pressurePercentile: 0.05,
            humidity: 90, precipitationChance: 90, precipitationAmount: 5,
            temperatureChange3h: -8
        )
        #expect(result.factors.pressureChange == 8)
        #expect(result.factors.pressureBaseline == 3)
        #expect(result.factors.pressure == 11)      // 分割前と同じ値になること
        #expect(result.factors.humidity == 3)
        #expect(result.factors.precipitation == 2)
        #expect(result.factors.temperature == 2)
        #expect(result.score == 18)                 // 設計上の最大値
        #expect(result.level == .danger)
    }

    @Test("穏やかな条件では安心レベルになる")
    func calmConditions() {
        let result = compositeRisk(
            pressureChanges: PressureChanges(oneHour: 0.5, threeHour: 1, sixHour: 1.5),
            pressurePercentile: 0.6,
            humidity: 50, precipitationChance: 10, precipitationAmount: 0,
            temperatureChange3h: 1
        )
        #expect(result.score == 0)
        #expect(result.level == .calm)
    }
}
