// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/HealthCheckIn.swift
// 本人が入力した体調を、記録処理へ渡すための値型。
// きあぼうの休む姿と、通知の個人化に使う体調データを区別するため。
// 関連: CheckInModel.swift, KiabouCheckInView.swift, docs/kiabou-integration.md
import Foundation

public enum HealthFeeling: String, Codable, Sendable {
    case good
    case bad
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
