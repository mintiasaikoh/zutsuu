/// リスクの 4 段階。src/index.ts の `type RiskLevel` の定義に合わせている。
/// SPEC.md には 5 段階と書かれているが、そちらが古い。
///
/// `rawValue` の 1〜4 は TypeScript 実装との移植契約であり、
/// 永続化キーとしても使うため変更しないこと。
public enum RiskLevel: Int, Sendable, Comparable, CaseIterable {
    /// 安心
    case calm = 1
    /// やや注意
    case slight = 2
    /// 注意
    case caution = 3
    /// 危険
    case danger = 4

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
