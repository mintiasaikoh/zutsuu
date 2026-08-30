import Testing
import Foundation
@testable import RiskEngine

@Suite("時系列の変化量")
struct PressureChangeTests {

    @Test("N時間前との差を取る")
    func overHours() {
        let series = makeSeries(pressures: [1010, 1008, 1006, 1004, 1002, 1000, 998])
        #expect(pressureChange(series, at: 6, hoursAgo: 1) == -2)
        #expect(pressureChange(series, at: 6, hoursAgo: 3) == -6)
        #expect(pressureChange(series, at: 6, hoursAgo: 6) == -12)
    }

    @Test("過去データが足りない場合は0を返す")
    func insufficientHistory() {
        let series = makeSeries(pressures: [1010, 1008, 1006])
        #expect(pressureChange(series, at: 0, hoursAgo: 1) == 0)
        #expect(pressureChange(series, at: 2, hoursAgo: 6) == 0)
    }

    @Test("気温の変化量も同じ規則で取れる")
    func temperature() {
        let series = makeSeries(pressures: [1013, 1013, 1013, 1013],
                                temperatures: [10, 13, 16, 19])
        #expect(temperatureChange(series, at: 3, hoursAgo: 3) == 9)
    }

    @Test("3つの時間窓をまとめて取れる")
    func aggregate() {
        let series = makeSeries(pressures: [1010, 1008, 1006, 1004, 1002, 1000, 998])
        let changes = pressureChanges(series, at: 6)
        #expect(changes.oneHour == -2)
        #expect(changes.threeHour == -6)
        #expect(changes.sixHour == -12)
    }
}
