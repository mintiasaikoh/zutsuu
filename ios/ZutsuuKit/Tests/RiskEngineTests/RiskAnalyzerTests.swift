import Testing
import Foundation
import RiskEngine

@Suite("時系列リスク解析")
struct RiskAnalyzerTests {

    @Test("各時刻のリスクが算出される")
    func onePerPoint() {
        let series = makeSeries(pressures: Array(repeating: 1013, count: 24))
        let analyzer = RiskAnalyzer(climatology: StubClimatology(value: 0.5),
                                    latitude: 35.7, longitude: 139.6)
        let result = analyzer.analyze(series)
        #expect(result.count == 24)
        #expect(result.allSatisfy { $0.assessment.level == .calm })
    }

    @Test("気圧が急降下する区間でリスクが上がる")
    func detectsPressureDrop() {
        var pressures = [Double](repeating: 1013, count: 12)
        pressures += stride(from: 1011.0, through: 995.0, by: -2.0)
        let analyzer = RiskAnalyzer(climatology: StubClimatology(value: 0.5),
                                    latitude: 35.7, longitude: 139.6)
        let result = analyzer.analyze(makeSeries(pressures: pressures))
        #expect(result.last!.assessment.level >= .caution)
    }

    @Test("空の系列を渡しても落ちない")
    func emptySeries() {
        let analyzer = RiskAnalyzer(climatology: StubClimatology(value: 0.5),
                                    latitude: 0, longitude: 0)
        #expect(analyzer.analyze([]).isEmpty)
    }

    // MARK: - 平年分布への引数の受け渡し
    //
    // `StubClimatology` は引数を捨てて定数を返すため、`RiskAnalyzer` が
    // 緯度・経度・月・気圧を正しく渡しているかを何も検証していない。
    // 以下は「渡した引数でだけ低パーセンタイルを返す」stub を使い、
    // 受け渡しの誤り（`.month` の取り違え、緯度経度の入れ替え、
    // 別の地点の気圧を渡す等）を pressureBaseline の値で観測する。

    /// 1 月のときだけ「その土地としては低い」を返す。
    private func januaryOnly() -> ClosureClimatology {
        ClosureClimatology { _, _, _, month in month == 1 ? 0.05 : 0.5 }
    }

    @Test("観測日時の月が平年分布に渡される")
    func passesMonth() {
        let analyzer = RiskAnalyzer(climatology: januaryOnly(),
                                    latitude: 35.7, longitude: 139.6,
                                    calendar: utcCalendar)
        let january = makeSeries(pressures: [1013, 1013, 1013],
                                 start: utcDate(year: 2026, month: 1, day: 20))
        #expect(analyzer.analyze(january).allSatisfy { $0.assessment.factors.pressureBaseline == 3 })
    }

    @Test("別の月ではその月の分布が使われる")
    func passesMonthJuly() {
        let analyzer = RiskAnalyzer(climatology: januaryOnly(),
                                    latitude: 35.7, longitude: 139.6,
                                    calendar: utcCalendar)
        let july = makeSeries(pressures: [1013, 1013, 1013],
                              start: utcDate(year: 2026, month: 7, day: 15))
        #expect(analyzer.analyze(july).allSatisfy { $0.assessment.factors.pressureBaseline == 0 })
    }

    @Test("緯度と経度が入れ替わらずに渡される")
    func passesCoordinates() {
        let tokyoOnly = ClosureClimatology { _, latitude, longitude, _ in
            (latitude == 35.7 && longitude == 139.6) ? 0.05 : 0.5
        }
        let analyzer = RiskAnalyzer(climatology: tokyoOnly, latitude: 35.7, longitude: 139.6)
        let result = analyzer.analyze(makeSeries(pressures: [1013, 1013, 1013]))
        #expect(result.allSatisfy { $0.assessment.factors.pressureBaseline == 3 })
    }

    @Test("各時刻の気圧がその時刻の判定に渡される")
    func passesPressureOfEachPoint() {
        let lowOnly = ClosureClimatology { pressure, _, _, _ in pressure == 980 ? 0.05 : 0.5 }
        let analyzer = RiskAnalyzer(climatology: lowOnly, latitude: 35.7, longitude: 139.6)
        let result = analyzer.analyze(makeSeries(pressures: [1013, 1013, 980, 1013]))
        #expect(result.map(\.assessment.factors.pressureBaseline) == [0, 0, 3, 0])
    }

    @Test("各時刻の気圧変化量が結果に含まれる")
    func exposesPressureChanges() {
        let analyzer = RiskAnalyzer(climatology: StubClimatology(value: 0.5),
                                    latitude: 35.7, longitude: 139.6)
        let result = analyzer.analyze(makeSeries(pressures: [1010, 1008, 1006, 1004]))
        #expect(result[3].pressureChanges == PressureChanges(oneHour: -2, threeHour: -6, sixHour: 0))
        #expect(result[3].point.pressure == 1004)
    }
}
