import Testing
@testable import RiskEngine

@Suite("湿度・降水・気温スコア")
struct OtherScoreTests {

    @Test("湿度スコア", arguments: [(74.0, 0), (75.0, 1), (84.0, 1), (85.0, 2), (100.0, 2)])
    func humidity(value: Double, expected: Int) {
        #expect(humidityScore(humidity: value, pressureChange3h: 0) == expected)
    }

    @Test("高湿度と気圧低下が重なるとボーナス1pt")
    func humidityPressureCombo() {
        #expect(humidityScore(humidity: 80, pressureChange3h: -4) == 2)
        #expect(humidityScore(humidity: 80, pressureChange3h: -3.9) == 1)   // 閾値未満
        #expect(humidityScore(humidity: 74, pressureChange3h: -10) == 0)    // 湿度が足りない
        #expect(humidityScore(humidity: 90, pressureChange3h: -5) == 3)     // 上限 3pt
    }

    @Test("降水スコア", arguments: [(59.0, 0), (60.0, 1), (79.0, 1), (80.0, 2), (100.0, 2)])
    func precipitation(chance: Double, expected: Int) {
        #expect(precipitationScore(chance: chance, amount: 0) == expected)
    }

    @Test("降水量が多いと加点されるが上限は2pt")
    func precipitationAmountBonus() {
        #expect(precipitationScore(chance: 0, amount: 3) == 1)
        #expect(precipitationScore(chance: 0, amount: 2) == 0)      // 2mm ちょうどは加点しない
        #expect(precipitationScore(chance: 90, amount: 10) == 2)    // 上限で頭打ち
        // 確率で 1pt 取っている状態からの加点。上限判定が `score < 1` だとここが 1pt になる。
        #expect(precipitationScore(chance: 60, amount: 3) == 2)
        #expect(precipitationScore(chance: 79, amount: 3) == 2)
    }

    @Test("気温変動スコア", arguments: [(0.0, 0), (4.9, 0), (5.0, 1), (7.9, 1), (8.0, 2), (-8.0, 2)])
    func temperature(change: Double, expected: Int) {
        #expect(temperatureScore(temperatureChange3h: change) == expected)
    }
}
