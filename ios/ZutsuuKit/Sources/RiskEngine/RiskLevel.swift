// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/RiskLevel.swift
// リスクの 4 段階。
// TypeScript 版との移植契約（rawValue 1〜4）を型で固定するため。
// 関連: CompositeRisk.swift, docs/riskengine-api.md §3.6
/// リスクの 4 段階。src/index.ts の `type RiskLevel` の定義に合わせている。
///
/// `rawValue` の 1〜4 は TypeScript 実装との移植契約であり、
/// 永続化キーとしても使うため変更しないこと。
public enum RiskLevel: Int, Sendable, Hashable, Comparable, CaseIterable {
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
