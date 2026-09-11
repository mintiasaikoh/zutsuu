// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouScenery.swift
// きあぼうの背景（舞台の絵）と、記録の累計日数による解放条件。
// 着せ替えと同じ「本人が選ぶ見返り」として背景を返すため（設計書 §6.7、kiabou-integration.md §3.3）。
// 関連: KiabouStage.swift, KiabouOutfit.swift, assets/kiabou/backgrounds/catalog.json
import Foundation

/// 選べる背景 1 つ。`resource` が nil なら無地（画像なし）。
/// `id` は `AppStorage`（`kiabou.scene`）の保存キーになるため変更禁止。
public struct KiabouScenery: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let requiredDays: Int
    /// 同梱ファイル名（拡張子込み）。`UIImage(named:)` は拡張子付きの名前でも解決できる。
    let resource: String?

    /// 無地。快適さの設定なので解放条件は付けない（設計書 §6.7）。
    public static let plain = KiabouScenery(id: "plain", name: String(localized: "むじ", bundle: .module), requiredDays: 0, resource: nil)
    /// 従来の入り江。最初から選べる。
    public static let cove = KiabouScenery(id: "cove", name: String(localized: "いりえ", bundle: .module), requiredDays: 0, resource: "cove.png")

    /// 表示順 = 解放順。ユーザー制作の 11 種は catalog.json の順に 5 日 / 10 日で解放。
    public static let all: [KiabouScenery] =
        [plain, cove]
        + user.prefix(5).map { user($0, requiredDays: 5) }
        + user.dropFirst(5).map { user($0, requiredDays: 10) }

    private static let user: [(id: String, name: String)] = [
        ("rainy-cafe", String(localized: "雨の日の喫茶店", bundle: .module)),
        ("sunset-rooftop", String(localized: "夕暮れの屋上", bundle: .module)),
        ("moonlit-cove", String(localized: "月夜の入り江", bundle: .module)),
        ("cloud-bed", String(localized: "雲の上の寝床", bundle: .module)),
        ("mage-study", String(localized: "魔法使いの書斎", bundle: .module)),
        ("forest-veranda", String(localized: "森の縁側", bundle: .module)),
        ("snow-window", String(localized: "雪の日の窓辺", bundle: .module)),
        ("underwater-garden", String(localized: "浅瀬の水庭", bundle: .module)),
        ("quiet-library", String(localized: "小さな図書室", bundle: .module)),
        ("moon-train", String(localized: "おやすみ列車", bundle: .module)),
        ("quiet-sea", String(localized: "きあぼうの海", bundle: .module)),
    ]

    private static func user(_ entry: (id: String, name: String), requiredDays: Int) -> KiabouScenery {
        KiabouScenery(id: entry.id, name: entry.name, requiredDays: requiredDays,
                      resource: "scene-\(entry.id).jpg")
    }

    /// 保存された id から復元する。未知の id は入り江に倒す。
    public static func scenery(id: String) -> KiabouScenery {
        all.first { $0.id == id } ?? cove
    }

    public func isUnlocked(recordedDays: Int) -> Bool {
        recordedDays >= requiredDays
    }
}
