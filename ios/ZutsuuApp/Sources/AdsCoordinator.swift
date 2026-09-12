// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/AdsCoordinator.swift
// 広告の方針（頻度制御・解放期限）と保存状態を持ち、画面からの合図を AdProvider に橋渡しする。
// 全画面広告は必ず AdPolicy の判定を通し、画面は「遷移した」「復帰した」と言うだけにするため（設計書 §8.2）。
// 関連: ../../ZutsuuAds/Sources/AdPolicy/*.swift, ../../ZutsuuAds/Sources/ZutsuuAds/AdProvider.swift, RootView.swift
import Foundation
import Observation
import AdPolicy
import ZutsuuAds

@MainActor @Observable
final class AdsCoordinator {
    private enum Key {
        static let interstitial = "ads.interstitial.state"
        static let appOpenLastShown = "ads.appOpen.lastShown"
        static let unlocks = "ads.unlocks"
    }

    let provider: any AdProvider
    /// 通知タップで前面に来た直後は true。遷移カウントと App Open の両方で「数えない」に使う。
    var launchedFromNotification = false
    private(set) var unlocks: RewardUnlocks
    private var interstitialState: InterstitialGate.State
    private var appOpenLastShown: Date?
    private var hasSeenFirstForeground = false
    private let interstitialGate = InterstitialGate()
    private let appOpenGate = AppOpenGate()
    private let defaults: UserDefaults

    init(provider: any AdProvider, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        let decoder = JSONDecoder()
        interstitialState = defaults.data(forKey: Key.interstitial)
            .flatMap { try? decoder.decode(InterstitialGate.State.self, from: $0) } ?? .init()
        unlocks = defaults.data(forKey: Key.unlocks)
            .flatMap { try? decoder.decode(RewardUnlocks.self, from: $0) } ?? .init()
        appOpenLastShown = defaults.object(forKey: Key.appOpenLastShown) as? Date
        interstitialState = interstitialGate.launched(interstitialState, now: Date())
        persist()
    }

    var isReady: Bool { provider.isReady }

    /// メイン画面の描画完了後に呼ぶ（設計書 §8.3。起動のクリティカルパスに乗せない）。
    func startAfterFirstFrame() {
        Task { await provider.start() }
    }

    /// タブ切り替えなどの画面遷移。頻度制御が通ったときだけインタースティシャルを出す。
    func noteTransition() {
        let now = Date()
        let result = interstitialGate.transition(interstitialState, now: now,
                                                 countsAsTransition: !launchedFromNotification)
        interstitialState = result.state
        persist()
        guard result.show else { return }
        Task {
            if await provider.presentInterstitial() == false {
                // 在庫が無かった。次の機会まで数え直しにならないよう、表示済みにしない。
                interstitialState.transitionsSinceShown = interstitialGate.transitionsPerAd
                interstitialState.shownToday -= 1
                interstitialState.lastShown = nil
                persist()
            }
        }
    }

    /// フォアグラウンド復帰。コールドスタート（最初の 1 回）と通知経由では出さない。
    func noteForeground() {
        let isColdStart = !hasSeenFirstForeground
        hasSeenFirstForeground = true
        // 起動時オフラインで同意の取得に失敗した場合の再試行（レビュー R14）。
        if !isColdStart, !provider.isReady { startAfterFirstFrame() }
        defer { launchedFromNotification = false }
        guard appOpenGate.shouldShow(lastShown: appOpenLastShown, now: Date(), isColdStart: isColdStart,
                                     launchedFromNotification: launchedFromNotification) else { return }
        Task {
            if await provider.presentAppOpen() {
                appOpenLastShown = Date()
                persist()
            }
        }
    }

    func isUnlocked(_ perk: RewardPerk) -> Bool {
        unlocks.isUnlocked(perk, now: Date())
    }

    /// リワード動画を見て解放する。視聴完了しなければ何も変えない。
    func unlock(_ perk: RewardPerk) async -> Bool {
        guard await provider.presentRewarded() else { return false }
        unlocks = unlocks.granting(perk, now: Date())
        persist()
        return true
    }

    private func persist() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(interstitialState), forKey: Key.interstitial)
        defaults.set(try? encoder.encode(unlocks), forKey: Key.unlocks)
        defaults.set(appOpenLastShown, forKey: Key.appOpenLastShown)
    }
}
