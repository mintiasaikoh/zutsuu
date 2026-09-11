// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/KiabouUITests/KiabouOutfitTests.swift
// 着せ替えの解放条件・id の安定性・素材の同梱を検証する。
// 「選べます」と言った姿の素材が実は入っていない、を防ぐため。
// 関連: ../../Sources/KiabouUI/KiabouOutfit.swift, docs/kiabou-integration.md §3.2
import Testing
import Foundation
@testable import KiabouUI

@Suite("きあぼうの着せ替え")
struct KiabouOutfitTests {

    @Test("原型は最初から、色は3日、模様は7日で解放される")
    func unlockThresholds() {
        #expect(KiabouOutfit.original.isUnlocked(recordedDays: 0))
        let colors = KiabouOutfit.all.filter { $0.requiredDays == 3 }
        let patterns = KiabouOutfit.all.filter { $0.requiredDays == 7 }
        #expect(colors.count == 3)
        #expect(patterns.count == 3)
        for outfit in colors {
            #expect(!outfit.isUnlocked(recordedDays: 2))
            #expect(outfit.isUnlocked(recordedDays: 3))
        }
        for outfit in patterns {
            #expect(!outfit.isUnlocked(recordedDays: 6))
            #expect(outfit.isUnlocked(recordedDays: 7))
        }
    }

    /// 衣装ペルソナ 5 種は模様の次の段（累計 14 日）で解放される。
    @Test("衣装ペルソナは5種あり14日で解放される")
    func personaThresholds() {
        let personas = KiabouOutfit.all.filter { $0.requiredDays == 14 }
        #expect(personas.count == 5)
        #expect(Set(personas.map(\.id)) == ["gyaru-costume", "punk-costume", "cafe-costume",
                                           "mage-costume", "rapper-costume"])
        for outfit in personas {
            #expect(!outfit.isUnlocked(recordedDays: 13))
            #expect(outfit.isUnlocked(recordedDays: 14))
        }
        #expect(KiabouOutfit.outfit(id: "cafe-costume").name == "かふぇ")
    }

    @Test("idは一意で、未知のidは原型に倒れる")
    func idsAreStable() {
        #expect(Set(KiabouOutfit.all.map(\.id)).count == KiabouOutfit.all.count)
        #expect(KiabouOutfit.outfit(id: "original") == .original)
        #expect(KiabouOutfit.outfit(id: "kasumi-plain").name == "かすみ")
        #expect(KiabouOutfit.outfit(id: "そんな姿はない") == .original)
    }

    /// 解放を予告した姿の USDZ が同梱されていること。素材のコピー漏れは
    /// 実行時に「読み込み失敗 → 画像なし」で静かに壊れるため、ここで固定する。
    @Test("全外観の泳ぐ姿・休む姿の素材が同梱されている")
    func resourcesAreBundled() {
        for outfit in KiabouOutfit.all {
            for resource in [outfit.swimResource, outfit.coveredResource] {
                #expect(Bundle.module.url(forResource: resource, withExtension: nil) != nil,
                        "missing \(resource)")
            }
        }
    }
}
