// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouBedding.swift
// 休むときの枕と毛布の色系統。着せ替えの「小物だけの交換」（設計書 §6.7、kiabou-integration.md §3.2）。
// 体（rest-body）と寝具を別々に選べるようにし、covered 一式の差し替えから部品の組み立てへ移すため。
// 関連: KiabouOutfit.swift, KiabouScene.swift, assets/kiabou/variations/ASSETS.md
import Foundation

/// 枕と毛布の選択。値は `AppStorage`（`kiabou.pillow` / `kiabou.blanket`）の保存キーなので変更禁止。
/// `match` は「おそろい」= 姿と同じ色系統。
public struct KiabouBedding: Sendable, Equatable, Hashable {
    public var pillow: String
    public var blanket: String

    public static let matchID = "match"
    public static let matching = KiabouBedding(pillow: matchID, blanket: matchID)

    public init(pillow: String, blanket: String) {
        self.pillow = pillow
        self.blanket = blanket
    }

    /// 選べる色系統。`requiredDays` はその色の姿（色だけ）と同じ累計 3 日。
    public struct Choice: Identifiable, Sendable, Equatable, Hashable {
        public let id: String
        public let name: String
        public let requiredDays: Int
        public func isUnlocked(recordedDays: Int) -> Bool { recordedDays >= requiredDays }
    }

    public static let choices: [Choice] = [
        Choice(id: matchID, name: String(localized: "おそろい", bundle: .module), requiredDays: 0),
        Choice(id: "kasumi", name: String(localized: "かすみ", bundle: .module), requiredDays: 3),
        Choice(id: "shizuku", name: String(localized: "しずく", bundle: .module), requiredDays: 3),
        Choice(id: "komorebi", name: String(localized: "こもれび", bundle: .module), requiredDays: 3),
    ]

    /// 姿の色系統を当てはめた実際の枕・毛布の系統。未知の id は「おそろい」に倒す。
    func resolved(family: String) -> (pillow: String, blanket: String) {
        func pick(_ id: String) -> String {
            Self.choices.contains { $0.id == id && id != Self.matchID } ? id : family
        }
        return (pick(pillow), pick(blanket))
    }

    static func pillowResource(_ family: String) -> String { "pillow-\(family).usdz" }
    static func blanketResource(_ family: String) -> String { "blanket-\(family).usdz" }
    static let bedResource = "bed.usdz"
}
