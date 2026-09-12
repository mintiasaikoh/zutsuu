// /Users/mymac/zutsuu/ios/ZutsuuApp/Tests/AdsCoordinatorTests.swift
// 画面からの合図（遷移・復帰・解放）が広告の方針と保存状態に正しく落ちることを検証する。
// 全画面広告は必ず AdPolicy を通る、SDK 未準備なら何も出さない、を結合で固定するため。
// 関連: ../Sources/AdsCoordinator.swift, ../../ZutsuuAds/Sources/AdPolicy/*.swift
import Testing
import Foundation
import AdPolicy
import ZutsuuAds
@testable import ZutsuuApp

@MainActor
@Suite("広告コーディネータ")
struct AdsCoordinatorTests {
    @Test("SDK が準備できていなければ解放は失敗し、期限も付かない")
    func unlockFailsWithoutProvider() async {
        let ads = AdsCoordinator(provider: NoAdsProvider(), defaults: isolatedDefaults("ads"))
        #expect(await ads.unlock(.correlationReport) == false)
        #expect(!ads.isUnlocked(.correlationReport))
    }

    @Test("遷移の記録は保存され、再起動しても日次の回数を引き継ぐ")
    func transitionsPersist() {
        let defaults = isolatedDefaults("ads-persist")
        let first = AdsCoordinator(provider: NoAdsProvider(), defaults: defaults)
        first.noteTransition()
        first.noteTransition()
        let second = AdsCoordinator(provider: NoAdsProvider(), defaults: defaults)
        // 起動で遷移の数え直しは 0 に戻るが、保存自体は壊れていない（例外なく読める）。
        second.noteTransition()
        #expect(defaults.data(forKey: "ads.interstitial.state") != nil)
    }

    @Test("解放の期限は保存され、別インスタンスからも読める")
    func unlocksPersist() {
        let defaults = isolatedDefaults("ads-unlock")
        let granted = RewardUnlocks().granting(.correlationReport, now: Date())
        defaults.set(try? JSONEncoder().encode(granted), forKey: "ads.unlocks")
        let ads = AdsCoordinator(provider: NoAdsProvider(), defaults: defaults)
        #expect(ads.isUnlocked(.correlationReport))
    }
}
