// /Users/mymac/zutsuu/ios/ZutsuuAds/Sources/ZutsuuAds/AdMobProvider.swift
// Google Mobile Ads SDK と UMP のラッパー。同意 → ATT → 初期化の順を守り、各フォーマットを先読みする。
// 同意前に SDK を起動しない・全画面広告は呼び出し側の頻度制御を通す、を 1 箇所で保証するため。
// 関連: AdProvider.swift, NativeAdCard.swift, docs/plans/2026-09-12-admob-plan4.md
#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform
import OSLog
import UIKit

@MainActor @Observable
public final class AdMobProvider: NSObject, AdProvider {
    public private(set) var isReady = false
    public private(set) var privacyOptionsRequired = false

    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var appOpen: AppOpenAd?
    @ObservationIgnored private var rewarded: RewardedAd?
    @ObservationIgnored private var started = false
    private let logger = Logger(subsystem: "com.mintiasaikoh.zutsuu", category: "ads")

    public override init() {
        super.init()
    }

    public func start() async {
        guard !started else { return }
        started = true
        await requestConsent()
        guard ConsentInformation.shared.canRequestAds else {
            logger.notice("広告の同意が得られていないため SDK を起動しない")
            return
        }
        await requestTracking()
        await MobileAds.shared.start()
        isReady = true
        await loadInterstitial()
        await loadAppOpen()
        await loadRewarded()
    }

    private func requestConsent() async {
        let parameters = RequestParameters()
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            if let root = Self.rootViewController {
                try await ConsentForm.loadAndPresentIfRequired(from: root)
            }
        } catch {
            logger.error("同意の取得に失敗: \(String(describing: error), privacy: .public)")
        }
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func requestTracking() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    public func presentPrivacyOptions() async {
        guard let root = Self.rootViewController else { return }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: root)
        } catch {
            logger.error("プライバシー設定の表示に失敗: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - 全画面

    public func presentInterstitial() async -> Bool {
        guard isReady, let ad = interstitial, let root = Self.rootViewController else { return false }
        interstitial = nil
        ad.present(from: root)
        await loadInterstitial()
        return true
    }

    public func presentAppOpen() async -> Bool {
        guard isReady, let ad = appOpen, let root = Self.rootViewController else { return false }
        appOpen = nil
        ad.present(from: root)
        await loadAppOpen()
        return true
    }

    public func presentRewarded() async -> Bool {
        guard isReady, let ad = rewarded, let root = Self.rootViewController else { return false }
        rewarded = nil
        let earned = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var rewardedFlag = false
            let watcher = RewardedWatcher(onDismiss: { continuation.resume(returning: rewardedFlag) })
            ad.fullScreenContentDelegate = watcher
            ad.present(from: root) { rewardedFlag = true }
            objc_setAssociatedObject(ad, &RewardedWatcher.key, watcher, .OBJC_ASSOCIATION_RETAIN)
        }
        await loadRewarded()
        return earned
    }

    // MARK: - 先読み

    private func loadInterstitial() async {
        interstitial = try? await InterstitialAd.load(with: AdUnitIDs.interstitial, request: Request())
    }

    private func loadAppOpen() async {
        appOpen = try? await AppOpenAd.load(with: AdUnitIDs.appOpen, request: Request())
    }

    private func loadRewarded() async {
        rewarded = try? await RewardedAd.load(with: AdUnitIDs.rewarded, request: Request())
    }

    static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
    }
}

/// リワード動画の閉じるタイミングを待つための delegate。
private final class RewardedWatcher: NSObject, FullScreenContentDelegate {
    nonisolated(unsafe) static var key = 0
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onDismiss()
    }
}
#endif
