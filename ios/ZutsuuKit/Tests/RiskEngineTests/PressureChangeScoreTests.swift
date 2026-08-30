import Testing
@testable import RiskEngine

@Suite("気圧変化スコア")
struct PressureChangeScoreTests {

    @Test("1時間変化のスコア", arguments: [
        (0.0, 0), (1.9, 0), (2.0, 1), (2.9, 1), (3.0, 2), (3.9, 2), (4.0, 3), (10.0, 3)
    ])
    func oneHour(change: Double, expected: Int) {
        let changes = PressureChanges(oneHour: change, threeHour: 0, sixHour: 0)
        #expect(pressureChangeScore(changes) == expected)
    }

    @Test("気圧上昇も下降と同じく評価される")
    func symmetric() {
        let falling = PressureChanges(oneHour: -4, threeHour: 0, sixHour: 0)
        let rising = PressureChanges(oneHour: 4, threeHour: 0, sixHour: 0)
        #expect(pressureChangeScore(falling) == pressureChangeScore(rising))
    }

    @Test("3時間変化のスコア", arguments: [(3.9, 0), (4.0, 1), (6.0, 2), (8.0, 3)])
    func threeHour(change: Double, expected: Int) {
        #expect(pressureChangeScore(PressureChanges(oneHour: 0, threeHour: change, sixHour: 0)) == expected)
    }

    @Test("6時間変化のスコア", arguments: [(5.9, 0), (6.0, 1), (10.0, 2)])
    func sixHour(change: Double, expected: Int) {
        #expect(pressureChangeScore(PressureChanges(oneHour: 0, threeHour: 0, sixHour: change)) == expected)
    }

    @Test("3つの変化量は加算される（最大8pt）")
    func accumulates() {
        #expect(pressureChangeScore(PressureChanges(oneHour: -5, threeHour: -9, sixHour: -12)) == 8)
    }
}
