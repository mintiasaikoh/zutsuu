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

    /// 湿度ボーナスが読む気圧変化は 3h の窓であることを固定する。
    /// 1h・3h・6h を互いに別の側へ置くことで、`compositeRisk` が
    /// `humidityScore(pressureChange3h:)` へどの窓を渡しているかを内訳で見分けられる。
    /// 湿度 80 は単独では 1pt。ボーナス（-4hPa 以下）が乗ると 2pt になる。
    @Test("湿度ボーナスには3時間窓の気圧変化が渡される")
    func humidityBonusUsesThreeHourWindow() {
        // 6h だけが閾値を超える。6h を渡す実装なら 2pt になる。
        let sixHourOnly = compositeRisk(
            pressureChanges: PressureChanges(oneHour: -1, threeHour: -1, sixHour: -6),
            pressurePercentile: 0.5,
            humidity: 80, precipitationChance: 0, precipitationAmount: 0,
            temperatureChange3h: 0
        )
        #expect(sixHourOnly.factors.humidity == 1)

        // 1h だけが閾値を超える。1h を渡す実装なら 2pt になる。
        let oneHourOnly = compositeRisk(
            pressureChanges: PressureChanges(oneHour: -6, threeHour: -1, sixHour: -1),
            pressurePercentile: 0.5,
            humidity: 80, precipitationChance: 0, precipitationAmount: 0,
            temperatureChange3h: 0
        )
        #expect(oneHourOnly.factors.humidity == 1)

        // 3h が閾値を超えればボーナスが乗る（同じ湿度で 2pt）。
        let threeHour = compositeRisk(
            pressureChanges: PressureChanges(oneHour: -1, threeHour: -6, sixHour: -1),
            pressurePercentile: 0.5,
            humidity: 80, precipitationChance: 0, precipitationAmount: 0,
            temperatureChange3h: 0
        )
        #expect(threeHour.factors.humidity == 2)
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
