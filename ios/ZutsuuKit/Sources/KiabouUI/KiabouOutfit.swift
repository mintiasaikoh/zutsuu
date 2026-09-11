// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouOutfit.swift
// きあぼうの外観（着せ替え）と、記録の累計日数による解放条件。
// 記録の見返りを本人が選べる姿として返すため（設計書 §6.7）。
// 関連: KiabouScene.swift, docs/kiabou-integration.md §3.2, assets/kiabou/variations/README.md
import Foundation

/// 選べる外観 1 つ。同梱 USDZ の泳ぐ姿・休む姿と、解放に必要な累計記録日数を持つ。
///
/// 解放は**連続ではなく累計**の記録日数。休んでも取り上げない（設計書 §6.7）。
/// `id` は `AppStorage` の保存キーになるため変更禁止。
public struct KiabouOutfit: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let requiredDays: Int
    let swimResource: String
    /// 休む姿一式。`family` のある姿では使わず（同梱もしない）、rest-body + 寝具を組み立てる（KiabouBedding）。
    let coveredResource: String
    /// 色系統（かすみ・しずく・こもれび）。寝具の「おそろい」と rest-body の解決に使う。
    /// 原型・衣装ペルソナは nil（部品素材がないので covered をそのまま使う）。
    public let family: String?
    var restBodyResource: String? { family.map { _ in "rest-body-\(id).usdz" } }

    /// 原型。最初から選べる。
    public static let original = KiabouOutfit(
        id: "original", name: String(localized: "いつもの", bundle: .module), requiredDays: 0,
        swimResource: "kiabou.usdz", coveredResource: "covered.usdz", family: nil)

    /// 表示順 = 解放順。色だけ（3 日）→ 模様あり（7 日）→ 衣装ペルソナ（14 日）。
    public static let all: [KiabouOutfit] =
        [original]
        + families.map { family in variation(family, style: "plain", requiredDays: 3) }
        + families.map { family in variation(family, style: "pattern", requiredDays: 7,
                                             suffix: String(localized: "・模様", bundle: .module)) }
        + personas.map { persona in variation(persona, style: "costume", requiredDays: 14,
                                              family: false) }

    private static let families: [(id: String, name: String)] =
        [("kasumi", String(localized: "かすみ", bundle: .module)),
         ("shizuku", String(localized: "しずく", bundle: .module)),
         ("komorebi", String(localized: "こもれび", bundle: .module))]

    /// 衣装ペルソナ（assets/kiabou/personas、2026-09-11 採用）。
    private static let personas: [(id: String, name: String)] =
        [("gyaru", String(localized: "ぎゃる", bundle: .module)),
         ("punk", String(localized: "ぱんく", bundle: .module)),
         ("cafe", String(localized: "かふぇ", bundle: .module)),
         ("mage", String(localized: "まほうつかい", bundle: .module)),
         ("rapper", String(localized: "らっぱー", bundle: .module))]

    private static func variation(_ family: (id: String, name: String), style: String,
                                  requiredDays: Int, suffix: String = "",
                                  family hasFamily: Bool = true) -> KiabouOutfit {
        KiabouOutfit(id: "\(family.id)-\(style)", name: family.name + suffix,
                     requiredDays: requiredDays,
                     swimResource: "swim-\(family.id)-\(style).usdz",
                     coveredResource: "covered-\(family.id)-\(style).usdz",
                     family: hasFamily ? family.id : nil)
    }

    /// 保存された id から復元する。未知の id（将来の削除・改名）は原型に倒す。
    public static func outfit(id: String) -> KiabouOutfit {
        all.first { $0.id == id } ?? original
    }

    public func isUnlocked(recordedDays: Int) -> Bool {
        recordedDays >= requiredDays
    }
}
