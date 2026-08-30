/// リスク判定の結果。`HourlyRisk` 経由でアプリ層へ公開される。
/// memberwise init は internal のまま（エンジン内部でのみ生成する）。
public struct RiskAssessment: Sendable, Equatable {
    public let level: RiskLevel
    public let score: Int
    public let factors: RiskFactors
}
