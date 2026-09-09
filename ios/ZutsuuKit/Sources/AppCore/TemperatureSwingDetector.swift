// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/TemperatureSwingDetector.swift
// 昨日と今日の最高気温を系列から切り出し、寒暖差の判定を組み立てる。
// 日境界・欠損時の扱いを、エンジンではなくアプリ層の決定として 1 箇所に置くため。
// 関連: ../RiskEngine/TemperatureSwing.swift, docs/appcore-api.md, docs/riskengine-api.md §2.1
import Foundation
import RiskEngine

public enum TemperatureSwingDetector {
    /// `now` を含む暦日を「今日」、その前日を「昨日」として、各日の最高気温を比較する。
    ///
    /// - 日境界は渡された `calendar`（タイムゾーン込み）で切る。既定値を置かないのは、
    ///   `.current` が暗黙に混ざると系列のタイムゾーンとずれても気付けないため
    /// - どちらかの日に点が 1 つもなければ `nil`。「寒暖差なし」とは区別する
    /// - 今日の最高気温は系列にある点だけから取る。朝の時点では予報値を含み、
    ///   系列が今日の途中までしかなければその範囲の最大になる。系列は昨日 00:00 から
    ///   今日いっぱいを含めて渡すこと
    public static func detect(in series: [WeatherPoint], now: Date,
                              calendar: Calendar) -> TemperatureSwing? {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return nil
        }
        let todayMax = maxTemperature(in: series, from: today, to: tomorrow)
        let yesterdayMax = maxTemperature(in: series, from: yesterday, to: today)
        guard let todayMax, let yesterdayMax else { return nil }
        return TemperatureSwing(todayMax: todayMax, yesterdayMax: yesterdayMax)
    }

    private static func maxTemperature(in series: [WeatherPoint], from start: Date,
                                       to end: Date) -> Double? {
        series.lazy
            .filter { $0.date >= start && $0.date < end }
            .map(\.temperature)
            .max()
    }
}
