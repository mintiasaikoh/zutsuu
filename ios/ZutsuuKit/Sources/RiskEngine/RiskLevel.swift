/// リスクの 4 段階。src/index.ts:16 の定義に合わせている。
/// SPEC.md には 5 段階と書かれているが、そちらが古い。
public enum RiskLevel: Int, Sendable, Comparable, CaseIterable {
    case calm = 1      // 安心
    case slight = 2    // やや注意
    case caution = 3   // 注意
    case danger = 4    // 危険

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
