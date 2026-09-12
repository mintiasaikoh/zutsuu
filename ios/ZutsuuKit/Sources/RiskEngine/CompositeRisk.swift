// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/CompositeRisk.swift
// 気圧・湿度・降水・気温変動の点数を合計し、18pt 満点のリスク判定にする。
// 要因ごとの点数と合計・レベルを 1 箇所で確定させ、表示と通知が同じ判定を使うため。
// 関連: Scoring.swift, RiskFactors.swift, docs/riskengine-api.md §3
/// スコアからリスクレベルへの変換。閾値は src/index.ts の computeCompositeRisk に一致させている。
func riskLevel(forScore score: Int) -> RiskLevel {
    if score >= 7 { return .danger }
    if score >= 4 { return .caution }
    if score >= 1 { return .slight }
    return .calm
}

/// 複合リスクスコア（最大 18pt）。
/// 気圧 11pt ＋ 湿度 3pt ＋ 降水 2pt ＋ 気温変動 2pt。
func compositeRisk(
    pressureChanges: PressureChanges,
    pressurePercentile: Double,
    humidity: Double, precipitationChance: Double, precipitationAmount: Double,
    temperatureChange3h: Double
) -> RiskAssessment {
    let factors = RiskFactors(
        pressureChange: pressureChangeScore(pressureChanges),
        pressureBaseline: absolutePressureScore(percentile: pressurePercentile),
        humidity: humidityScore(humidity: humidity, pressureChange3h: pressureChanges.threeHour),
        precipitation: precipitationScore(chance: precipitationChance, amount: precipitationAmount),
        temperature: temperatureScore(temperatureChange3h: temperatureChange3h)
    )
    return RiskAssessment(level: riskLevel(forScore: factors.total),
                          score: factors.total,
                          factors: factors)
}
