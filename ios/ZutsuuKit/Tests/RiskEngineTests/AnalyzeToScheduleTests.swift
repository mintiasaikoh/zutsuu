import Testing
import Foundation
import RiskEngine

/// `RiskAnalyzer.analyze` の出力をそのまま `AlertScheduler.schedule` に渡す合成のテスト。
///
/// 個々のスイートは片方の層しか通らない（解析側は曲線の値を、予約側は合成の曲線を見る）。
/// アプリ層が実際に書くのはこの 2 段の連結であり、その形でしか出ない不具合がある。
/// public API だけで書けることを保つため素の `import RiskEngine` を使う。
@Suite("解析から通知予約までの連結")
struct AnalyzeToScheduleTests {

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utcDate(year: 2026, month: 3, day: day, hour: hour, minute: minute)
    }

    /// 3/10 00:00 UTC から 1 時間刻みで 72 時間ぶんの予報。
    ///
    /// - index 21〜28: 8 時間で -24hPa の急降下（設計上の代表的な荒天）
    /// - index 29〜52: 24 時間かけてゆるやかに回復
    /// - index 69〜71: 予報の最終 3 時間に第二の前線が入る。
    ///   ここは前方窓が系列外に出るため評価できず、`analyze` は返さない。
    ///
    /// 気圧以外の入力（湿度 50%・降水なし・気温一定）は中立に置いてある。
    /// 期待値が気圧の項だけで決まり、内訳をそのまま読めるようにするため。
    private func stormySeries() -> [WeatherPoint] {
        var pressures = [Double](repeating: 1013, count: 21)
        pressures += (1...8).map { 1013 - 3 * Double($0) }
        pressures += (1...24).map { 989 + Double($0) }
        pressures += [Double](repeating: 1013, count: 16)
        pressures += [1009, 1005, 1001]
        precondition(pressures.count == 72)
        return makeSeries(pressures: pressures, start: at(10, 0))
    }

    private func analyzer() -> RiskAnalyzer {
        RiskAnalyzer(climatology: StubClimatology(value: 0.5), coordinate: tokyo,
                     calendar: utcCalendar)
    }

    /// 8 時間で 24hPa 下がる系列が、解析を経て 1 件の通知予約になる。
    ///
    /// `analyze` が末尾を切り詰める理由の説明（`RiskAnalyzer.swift`）は
    /// 「切り詰めないとこの規模の低下でも予約が 0 件になる」という主張だが、
    /// これまで固定されていたのは返る点数（66）だけで、
    /// 実際に予約が 1 件出ることは誰も表明していなかった。
    ///
    /// 変化量は前方差分なので、リスクが閾値を超えるのは低下が始まる **前** の 19:00
    /// （3h 窓が -6hPa を捉える時刻）。通知はその 90 分前の 17:30。
    /// 内訳のピークは 20:00 の 7pt（1h -3・3h -9・6h -18）。
    @Test("8時間で24hPa下がる予報が1件の予約になる")
    func stormProducesSingleAlert() throws {
        let curve = analyzer().analyze(stormySeries())
        #expect(curve.count == 66)

        let alerts = AlertScheduler(calendar: utcCalendar)
            .schedule(curve, now: at(9, 12), quietHours: QuietHours(start: 22, end: 8.5))

        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.targetDate == at(10, 19))
        #expect(alert.fireDate == at(10, 17, 30))
        #expect(alert.targetLevel == .danger)
        #expect(alert.assessment.score == 7)
        #expect(alert.assessment.factors == RiskFactors(pressureChange: 7, pressureBaseline: 0,
                                                        humidity: 0, precipitation: 0,
                                                        temperature: 0))
    }

    /// 評価しきれない末尾を返さないことが、予約の件数として観測できる。
    ///
    /// 最終 3 時間の前線は 1h・3h の窓だけなら注意レベルに届くが、6h 窓が欠けており
    /// 本当の規模は分からない。`analyze` が末尾を返すと、この半端な評価がそのまま
    /// 2 件目の予約になる。切り詰めていれば次回の取得まで持ち越される。
    @Test("評価できない末尾からは予約が生まれない")
    func incompleteTailProducesNoAlert() {
        let curve = analyzer().analyze(stormySeries())
        #expect(curve.last?.point.date == at(12, 17))

        // 嵐が収まった 3/11 03:00 以降は最後まで閾値未満。
        // 件数を先に固定するのは、空配列に対して `allSatisfy` が真になるのを防ぐため。
        let afterStorm = curve.filter { $0.point.date >= at(11, 3) }
        #expect(afterStorm.count == 39)
        #expect(afterStorm.allSatisfy { $0.assessment.level < .caution })
    }
}
