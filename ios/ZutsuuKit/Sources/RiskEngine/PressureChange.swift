import Foundation

/// index から hoursAgo 時間前との気圧差。
/// 系列が 1 時間刻みであることを前提とする。
/// 過去データが足りない場合は 0（＝変化なし扱い）を返す。
/// これは安全側の挙動：データ不足を「急変」と誤判定して外れ通知を出すより、
/// 発火しないほうが信頼を損なわない。
func pressureChange(_ series: [WeatherPoint], at index: Int, hoursAgo: Int) -> Double {
    change(series, at: index, hoursAgo: hoursAgo) { $0.pressure }
}

func temperatureChange(_ series: [WeatherPoint], at index: Int, hoursAgo: Int) -> Double {
    change(series, at: index, hoursAgo: hoursAgo) { $0.temperature }
}

/// スコアリングが必要とする 3 つの時間窓をまとめて取る。
func pressureChanges(_ series: [WeatherPoint], at index: Int) -> PressureChanges {
    PressureChanges(oneHour: pressureChange(series, at: index, hoursAgo: 1),
                    threeHour: pressureChange(series, at: index, hoursAgo: 3),
                    sixHour: pressureChange(series, at: index, hoursAgo: 6))
}

private func change(_ series: [WeatherPoint], at index: Int, hoursAgo: Int,
                    value: (WeatherPoint) -> Double) -> Double {
    let past = index - hoursAgo
    guard past >= 0, index < series.count else { return 0 }
    return value(series[index]) - value(series[past])
}
