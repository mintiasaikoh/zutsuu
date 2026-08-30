/// リスク判定の結果。`HourlyRisk` 経由でアプリ層へ公開される。
public struct RiskAssessment: Sendable, Equatable {
    public let level: RiskLevel
    public let score: Int
    public let factors: RiskFactors
}

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
        humidity: humidityScore(humidity: humidity, change3h: pressureChanges.threeHour),
        precipitation: precipitationScore(chance: precipitationChance, amount: precipitationAmount),
        temperature: temperatureScore(change3h: temperatureChange3h)
    )
    return RiskAssessment(level: riskLevel(forScore: factors.total),
                          score: factors.total,
                          factors: factors)
}
