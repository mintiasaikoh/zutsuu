// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/PressureChange.swift
// 1 時間・3 時間・6 時間の気圧変化量の点数化。
// 気圧の「変化」を絶対値より重く扱う配点（§3.1）を 1 箇所に置くため。
// 関連: PressureChanges.swift, CompositeRisk.swift, docs/riskengine-api.md §3.1
/// index から hoursAhead 時間先との気圧差。
/// 系列が 1 時間刻みであることを前提とする。
///
/// 窓は「前方」に取る（`series[index + hoursAhead] - series[index]`）。
/// つまりスコアが答えるのは「この時刻から先、気圧がどれだけ変化するか」であり、
/// 「ここまでにどれだけ変化したか」ではない。
/// この向きにより、リスクは気圧低下の**始まり**の時刻で高くなる。
/// `AlertScheduler` が 90 分前倒しで通知するのは、低下が始まる前に薬を飲めるようにするためで、
/// 後方差分では低下の**終わり**にピークが来てしまい、この前倒しが低下の最中に着地する。
/// src/index.ts:239-242 と同じ意味論。
///
/// 先のデータが足りない場合（系列の末尾付近）は 0（＝変化なし扱い）を返す。
/// これは安全側の挙動：データ不足を「急変」と誤判定して外れ通知を出すより、
/// 発火しないほうが信頼を損なわない。
///
/// - Note: TypeScript 実装は 3h/6h の窓が range 外のとき `change1h * 3` / `change1h * 6` で
///   外挿するが、ここでは意図的に移植していない。1 時間分から 6 時間分の変化量を作るのは
///   データの捏造であり、誤通知は見逃しより信頼を損なう。加えて解析対象は 72 時間予報の
///   先頭 24 時間だけなので、この分岐は実質デッドコードでもある。復活させないこと。
func pressureChange(_ series: [WeatherPoint], at index: Int, hoursAhead: Int) -> Double {
    change(series, at: index, hoursAhead: hoursAhead) { $0.pressure }
}

func temperatureChange(_ series: [WeatherPoint], at index: Int, hoursAhead: Int) -> Double {
    change(series, at: index, hoursAhead: hoursAhead) { $0.temperature }
}

/// スコアリングが必要とする 3 つの時間窓をまとめて取る。
func pressureChanges(_ series: [WeatherPoint], at index: Int) -> PressureChanges {
    PressureChanges(oneHour: pressureChange(series, at: index, hoursAhead: 1),
                    threeHour: pressureChange(series, at: index, hoursAhead: 3),
                    sixHour: pressureChange(series, at: index, hoursAhead: 6))
}

private func change(_ series: [WeatherPoint], at index: Int, hoursAhead: Int,
                    value: (WeatherPoint) -> Double) -> Double {
    let future = index + hoursAhead
    guard series.indices.contains(index), series.indices.contains(future) else { return 0 }
    return value(series[future]) - value(series[index])
}
