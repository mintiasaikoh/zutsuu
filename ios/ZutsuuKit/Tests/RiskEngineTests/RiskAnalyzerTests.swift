import Testing
import Foundation
import RiskEngine

@Suite("時系列リスク解析")
struct RiskAnalyzerTests {

    private func analyzer(_ climatology: any PressureClimatology = StubClimatology(value: 0.5),
                          calendar: Calendar = .current) -> RiskAnalyzer {
        RiskAnalyzer(climatology: climatology, latitude: 35.7, longitude: 139.6, calendar: calendar)
    }

    @Test("各時刻のリスクが算出される")
    func onePerPoint() {
        let series = makeSeries(pressures: Array(repeating: 1013, count: 24))
        let result = analyzer().analyze(series)
        #expect(result.count == 24 - RiskAnalyzer.lookaheadHours)
        #expect(result.allSatisfy { $0.assessment.level == .calm })
    }

    /// 変化量は前方差分なので、リスクが上がるのは低下が**始まる**時刻（index 11）。
    /// index を特定して固定する。「どこかが上がっている」だけの表明では
    /// 前方・後方どちらでも通ってしまい、向きの誤りを検出できない。
    @Test("気圧が急降下し始める時刻でリスクが上がる")
    func detectsPressureDrop() {
        var pressures = [Double](repeating: 1013, count: 12)
        pressures += stride(from: 1011.0, through: 995.0, by: -2.0)
        let result = analyzer().analyze(makeSeries(pressures: pressures))
        #expect(result[11].assessment.level >= .caution)
        #expect(result[11].pressureChanges == PressureChanges(oneHour: -2, threeHour: -6, sixHour: -12))
    }

    /// 向きそのものを固定する回帰ガード。
    /// 下がって落ち着く系列では、低下の入口でスコアが高く、出口では低い。
    /// 後方差分に戻すとこの非対称が反転するため、このテストが落ちる。
    @Test("低下の入口でリスクが高く、落ち切った後は低い")
    func riskPeaksAtOnsetNotAtEnd() {
        let pressures: [Double] = [1013, 1011, 1009, 1007, 1005, 1003, 1001, 999,
                                   997, 995, 995, 995, 995, 995, 995, 995]
        let result = analyzer().analyze(makeSeries(pressures: pressures))
        #expect(result[0].assessment.factors.pressureChange == 5)
        #expect(result[0].assessment.level >= .caution)
        #expect(result[9].assessment.factors.pressureChange == 0)
        #expect(result[9].assessment.level == .calm)
    }

    @Test("空の系列を渡しても落ちない")
    func emptySeries() {
        #expect(analyzer().analyze([]).isEmpty)
    }

    // MARK: - 末尾の切り詰め
    //
    // 前方窓は系列の末尾 `lookaheadHours` 時間ぶんで系列外に出る。
    // そこを不完全な値で返すと「本物の平穏」と見分けが付かず、
    // 通知が静かに 0 件になる。返さないことでその欠落を呼び出し側から見えるようにする。

    @Test("前方窓が取れない末尾は返さない")
    func dropsIncompleteTail() {
        #expect(analyzer().analyze(makeSeries(pressures: Array(repeating: 1013, count: 72))).count == 66)
    }

    @Test("前方窓の深さに満たない系列は空になる")
    func tooShortSeriesIsEmpty() {
        #expect(analyzer().analyze(makeSeries(pressures: Array(repeating: 1013, count: 3))).isEmpty)
        #expect(analyzer().analyze(makeSeries(pressures: Array(repeating: 1013, count: 6))).isEmpty)
        #expect(analyzer().analyze(makeSeries(pressures: Array(repeating: 1013, count: 7))).count == 1)
    }

    /// 最後に返す要素は 6 時間先まで完全な窓を持つ。
    /// 系列の最終点にだけ落差を置き、それが最後の要素の 6h 窓に現れることで確かめる。
    @Test("最後に返す要素は完全な前方窓を持つ")
    func lastElementHasCompleteWindow() {
        var pressures = [Double](repeating: 1013, count: 72)
        pressures[71] = 1000
        let result = analyzer().analyze(makeSeries(pressures: pressures))
        #expect(result.count == 66)
        #expect(result.last!.pressureChanges == PressureChanges(oneHour: 0, threeHour: 0, sixHour: -13))
    }

    // MARK: - スコアリングへの引数の受け渡し
    //
    // `RiskAnalyzer` が各引数を正しい仮引数に渡しているかを、要因ごとの内訳で観測する。
    // 取り違え（緯度経度の入れ替え、湿度と降水確率の入れ替え、`.month` の取り違え、
    // 別の時刻の値を渡す等）が起きると、対応する factors の値が変わる。

    /// 1 月のときだけ「その土地としては低い」を返す。
    private func januaryOnly() -> ClosureClimatology {
        ClosureClimatology { _, _, _, month in month == 1 ? 0.05 : 0.5 }
    }

    private func baselines(_ result: [HourlyRisk]) -> [Int] {
        result.map(\.assessment.factors.pressureBaseline)
    }

    @Test("観測日時の月が平年分布に渡される")
    func passesMonth() {
        let january = makeSeries(pressures: Array(repeating: 1013, count: 10),
                                 start: utcDate(year: 2026, month: 1, day: 20))
        #expect(baselines(analyzer(januaryOnly(), calendar: utcCalendar).analyze(january)) == [3, 3, 3, 3])
    }

    @Test("別の月ではその月の分布が使われる")
    func passesMonthJuly() {
        let july = makeSeries(pressures: Array(repeating: 1013, count: 10),
                              start: utcDate(year: 2026, month: 7, day: 15))
        #expect(baselines(analyzer(januaryOnly(), calendar: utcCalendar).analyze(july)) == [0, 0, 0, 0])
    }

    @Test("緯度と経度が入れ替わらずに渡される")
    func passesCoordinates() {
        let tokyoOnly = ClosureClimatology { _, latitude, longitude, _ in
            (latitude == 35.7 && longitude == 139.6) ? 0.05 : 0.5
        }
        let series = makeSeries(pressures: Array(repeating: 1013, count: 10))
        #expect(baselines(analyzer(tokyoOnly).analyze(series)) == [3, 3, 3, 3])
    }

    @Test("各時刻の気圧がその時刻の判定に渡される")
    func passesPressureOfEachPoint() {
        let lowOnly = ClosureClimatology { pressure, _, _, _ in pressure == 980 ? 0.05 : 0.5 }
        var pressures = [Double](repeating: 1013, count: 10)
        pressures[2] = 980
        #expect(baselines(analyzer(lowOnly).analyze(makeSeries(pressures: pressures))) == [0, 0, 3, 0])
    }

    /// 湿度・降水確率・降水量が別々の仮引数に渡っていることを内訳で固定する。
    /// 湿度 90 は湿度 2pt、降水確率 0・降水量 3mm は降水 1pt。
    /// どの 2 つを入れ替えてもこの組み合わせは崩れる。
    @Test("湿度・降水確率・降水量が取り違えられずに渡される")
    func passesHumidityAndPrecipitation() {
        let series = makeSeries(pressures: Array(repeating: 1013, count: 10),
                                humidity: 90, precipitationChance: 0, precipitationAmount: 3)
        let result = analyzer().analyze(series)
        #expect(result.map(\.assessment.factors.humidity) == [2, 2, 2, 2])
        #expect(result.map(\.assessment.factors.precipitation) == [1, 1, 1, 1])
    }

    /// 3 時間先との気温差が渡ることを、時刻ごとに違う値で固定する。
    /// 定数（0 など）に差し替えると内訳が一律になり、この表明が落ちる。
    @Test("各時刻の3時間先との気温差が渡される")
    func passesTemperatureChange() {
        let series = makeSeries(pressures: Array(repeating: 1013, count: 10),
                                temperatures: [10, 13, 16, 19, 19, 19, 19, 19, 19, 19])
        let result = analyzer().analyze(series)
        #expect(result.map(\.assessment.factors.temperature) == [2, 1, 0, 0])
    }

    @Test("各時刻の気圧変化量が結果に含まれる")
    func exposesPressureChanges() {
        let series = makeSeries(pressures: [1010, 1008, 1006, 1004, 1002, 1000, 998, 996])
        let result = analyzer().analyze(series)
        #expect(result[0].pressureChanges == PressureChanges(oneHour: -2, threeHour: -6, sixHour: -12))
        #expect(result[0].point.pressure == 1010)
    }
}
