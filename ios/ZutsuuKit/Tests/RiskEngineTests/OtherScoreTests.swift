import Testing
@testable import RiskEngine

@Suite("湿度・降水・気温スコア")
struct OtherScoreTests {

    @Test("湿度スコア", arguments: [(74.0, 0), (75.0, 1), (84.0, 1), (85.0, 2), (100.0, 2)])
    func humidity(value: Double, expected: Int) {
        #expect(humidityScore(humidity: value, change3h: 0) == expected)
    }

    @Test("高湿度と気圧低下が重なるとボーナス1pt")
    func humidityPressureCombo() {
        #expect(humidityScore(humidity: 80, change3h: -4) == 2)
        #expect(humidityScore(humidity: 80, change3h: -3.9) == 1)
        #expect(humidityScore(humidity: 74, change3h: -10) == 0)
        #expect(humidityScore(humidity: 90, change3h: -5) == 3)
    }

    @Test("降水スコア", arguments: [(59.0, 0), (60.0, 1), (79.0, 1), (80.0, 2), (100.0, 2)])
    func precipitation(chance: Double, expected: Int) {
        #expect(precipitationScore(chance: chance, amount: 0) == expected)
    }

    @Test("降水量が多いと加点されるが上限は2pt")
    func precipitationAmountBonus() {
        #expect(precipitationScore(chance: 0, amount: 3) == 1)
        #expect(precipitationScore(chance: 0, amount: 2) == 0)
        #expect(precipitationScore(chance: 90, amount: 10) == 2)
    }

    @Test("気温変動スコア", arguments: [(0.0, 0), (4.9, 0), (5.0, 1), (7.9, 1), (8.0, 2), (-8.0, 2)])
    func temperature(change: Double, expected: Int) {
        #expect(temperatureScore(change3h: change) == expected)
    }
}
