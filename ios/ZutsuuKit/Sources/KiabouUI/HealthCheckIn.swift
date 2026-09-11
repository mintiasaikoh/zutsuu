// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/HealthCheckIn.swift
// 本人が入力した体調を、記録処理へ渡すための値型。
// きあぼうの休む姿と、通知の個人化に使う体調データを区別するため。
// 関連: CheckInModel.swift, KiabouCheckInView.swift, docs/kiabou-integration.md
import Foundation

/// rawValue は保存キー。変更・削除禁止（追加は可）。
/// 学習（PersonalRisk）は「悪い」か否かの二値で使う: `.good` と `.normal` は「悪くない」。
public enum HealthFeeling: String, Codable, Sendable, CaseIterable {
    case good
    case normal
    case bad

    /// 表示名（String Catalog でローカライズ。キーは日本語）。
    /// 「良い/悪い」は評価の語で硬いため、本人の感じ方に寄せた柔らかい言葉にする
    /// （2026-09-10、ユーザー要望）。きあぼうの世界に合わせてひらがな。
    public var label: String {
        switch self {
        case .good: String(localized: "げんき", bundle: .module)
        case .normal: String(localized: "ふつう", bundle: .module)
        case .bad: String(localized: "つらい", bundle: .module)
        }
    }
}

/// アプリ層は、この時刻に対応する気象データと一緒に保存する。
/// UIは保存・学習方式を決めず、明示された体調だけを渡す。
public struct HealthCheckIn: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let feeling: HealthFeeling

    public init(id: UUID = UUID(), date: Date = Date(), feeling: HealthFeeling) {
        self.id = id
        self.date = date
        self.feeling = feeling
    }
}
