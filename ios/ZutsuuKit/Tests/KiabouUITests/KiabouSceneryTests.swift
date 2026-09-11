// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/KiabouUITests/KiabouSceneryTests.swift
// 背景の解放条件・id の安定性・素材の同梱を検証する。
// 「選べます」と言った背景の画像が実は入っていない、を防ぐため。
// 関連: ../../Sources/KiabouUI/KiabouScenery.swift, docs/kiabou-integration.md §3.3
import Testing
import Foundation
@testable import KiabouUI

@Suite("きあぼうの背景")
struct KiabouSceneryTests {

    @Test("無地と入り江は最初から、11種は5日と10日で解放される")
    func unlockThresholds() {
        #expect(KiabouScenery.plain.isUnlocked(recordedDays: 0))
        #expect(KiabouScenery.cove.isUnlocked(recordedDays: 0))
        let early = KiabouScenery.all.filter { $0.requiredDays == 5 }
        let late = KiabouScenery.all.filter { $0.requiredDays == 10 }
        #expect(early.count == 5)
        #expect(late.count == 6)
        #expect(KiabouScenery.all.count == 13)
        for scenery in early {
            #expect(!scenery.isUnlocked(recordedDays: 4))
            #expect(scenery.isUnlocked(recordedDays: 5))
        }
        for scenery in late {
            #expect(!scenery.isUnlocked(recordedDays: 9))
            #expect(scenery.isUnlocked(recordedDays: 10))
        }
    }

    @Test("idは一意で、未知のidは入り江に倒れる")
    func idsAreStable() {
        #expect(Set(KiabouScenery.all.map(\.id)).count == KiabouScenery.all.count)
        #expect(KiabouScenery.scenery(id: "cove") == .cove)
        #expect(KiabouScenery.scenery(id: "rainy-cafe").name == "雨の日の喫茶店")
        #expect(KiabouScenery.scenery(id: "そんな背景はない") == .cove)
    }

    @Test("無地以外の全背景の画像が同梱されている")
    func resourcesAreBundled() {
        #expect(KiabouScenery.plain.resource == nil)
        for scenery in KiabouScenery.all where scenery.id != KiabouScenery.plain.id {
            let resource = scenery.resource ?? ""
            #expect(Bundle.module.url(forResource: resource, withExtension: nil) != nil,
                    "missing \(resource)")
        }
    }
}
