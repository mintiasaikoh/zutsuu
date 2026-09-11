// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/KiabouUITests/KiabouBeddingTests.swift
// 寝具の選択の解決・解放条件・部品素材の同梱を検証する。
// 組み立てに必要な部品が 1 つでも欠けると休む姿が出なくなるため、ここで固定する。
// 関連: ../../Sources/KiabouUI/KiabouBedding.swift, docs/kiabou-integration.md §3.2
import Testing
import Foundation
@testable import KiabouUI

@Suite("きあぼうの寝具")
struct KiabouBeddingTests {

    @Test("おそろいは姿の色系統に解決され、未知のidもおそろいに倒れる")
    func matchingResolvesToFamily() {
        #expect(KiabouBedding.matching.resolved(family: "kasumi") == ("kasumi", "kasumi"))
        let mixed = KiabouBedding(pillow: "shizuku", blanket: "komorebi")
        #expect(mixed.resolved(family: "kasumi") == ("shizuku", "komorebi"))
        let unknown = KiabouBedding(pillow: "そんな色はない", blanket: "match")
        #expect(unknown.resolved(family: "shizuku") == ("shizuku", "shizuku"))
    }

    @Test("おそろいは最初から、色系統は3日で解放される")
    func unlockThresholds() {
        let match = KiabouBedding.choices.first { $0.id == KiabouBedding.matchID }
        #expect(match?.isUnlocked(recordedDays: 0) == true)
        let colors = KiabouBedding.choices.filter { $0.id != KiabouBedding.matchID }
        #expect(colors.count == 3)
        for choice in colors {
            #expect(!choice.isUnlocked(recordedDays: 2))
            #expect(choice.isUnlocked(recordedDays: 3))
        }
    }

    /// 色の姿は rest-body を持ち、原型・衣装ペルソナは持たない。部品は全部同梱されていること。
    @Test("組み立てに使う部品素材が同梱されている")
    func partsAreBundled() {
        func bundled(_ resource: String) -> Bool {
            Bundle.module.url(forResource: resource, withExtension: nil) != nil
        }
        #expect(bundled(KiabouBedding.bedResource))
        for family in ["kasumi", "shizuku", "komorebi"] {
            #expect(bundled(KiabouBedding.pillowResource(family)), "\(family)")
            #expect(bundled(KiabouBedding.blanketResource(family)), "\(family)")
        }
        let families = KiabouOutfit.all.filter { $0.family != nil }
        #expect(families.count == 6)
        for outfit in families {
            #expect(bundled(outfit.restBodyResource ?? ""), "\(outfit.id)")
        }
        #expect(KiabouOutfit.original.family == nil)
        #expect(KiabouOutfit.outfit(id: "cafe-costume").family == nil)
    }
}
