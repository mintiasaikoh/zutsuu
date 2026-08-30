/// リスク判定の結果。`HourlyRisk` 経由でアプリ層へ公開される。
/// エンジンが算出するのが本来の生成経路だが、SwiftUI プレビューや
/// テストが合成のリスク曲線を組み立てられるよう init も公開している。
public struct RiskAssessment: Sendable, Hashable {
    public let level: RiskLevel
    public let score: Int
    public let factors: RiskFactors

    public init(level: RiskLevel, score: Int, factors: RiskFactors) {
        self.level = level
        self.score = score
        self.factors = factors
    }
}
