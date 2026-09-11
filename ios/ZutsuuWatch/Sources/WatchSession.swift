// /Users/mymac/zutsuu/ios/ZutsuuWatch/Sources/WatchSession.swift
// Watch 側の WatchConnectivity。iPhone の要約を App Group に保存し、記録を到達保証つきで送る。
// コンプリケーション（別プロセス）が同じ要約を読めるよう App Group に置き、記録は iPhone 未起動でも失わないため。
// 関連: ZutsuuWatchApp.swift, WatchRootView.swift, ../../ZutsuuApp/Sources/WatchSessionBridge.swift
import Foundation
import Observation
import WatchConnectivity
import WidgetKit
import AppCore
import KiabouUI
import RiskEngine

/// App Group の UserDefaults に置く要約のキー。ウィジェット側と共有する。
enum WatchShared {
    static let appGroup = "group.com.mintiasaikoh.zutsuu"
    static let contextKey = "watch.context"
    static let widgetKind = "ZutsuuComplication"

    static func loadContext() -> WatchContext? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: contextKey) else { return nil }
        return try? WatchContext.decode(data)
    }
}

@MainActor @Observable
final class WatchSession: NSObject {
    private(set) var context: WatchContext? = WatchShared.loadContext()
    private(set) var lastRecorded: HealthFeeling?
    private(set) var isReachableToPhone = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 現在時刻のレベル。要約が無い・古い場合は nil。
    var currentLevel: RiskLevel? { context?.level(at: Date()) }

    /// 記録は iPhone に届いてから保存される。ここでは送るだけで、完了表示も「送ったよ」に留める。
    /// iPhone が届く範囲なら即時の sendMessage、届かなければ到達保証のある transferUserInfo。
    /// 両方届いても iPhone 側は同じ id を重複保存しない（kiabou-integration.md §2.2）。
    func record(_ feeling: HealthFeeling) {
        let checkIn = WatchCheckIn(id: UUID(), date: Date(), feeling: feeling.rawValue)
        guard let data = try? checkIn.encoded() else { return }
        let payload = [WatchSessionBridgeKeys.checkInKey: data]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
        lastRecorded = feeling
    }

    private func store(_ data: Data) {
        guard let decoded = try? WatchContext.decode(data) else { return }
        UserDefaults(suiteName: WatchShared.appGroup)?.set(data, forKey: WatchShared.contextKey)
        context = decoded
        WidgetCenter.shared.reloadTimelines(ofKind: WatchShared.widgetKind)
    }
}

/// iPhone 側 `WatchSessionBridge` と同じキー。両側で揃えること。
enum WatchSessionBridgeKeys {
    static let contextKey = "context"
    static let checkInKey = "checkIn"
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // Data だけを取り出して渡す（辞書と WCSession は Sendable でない）。
        let data = session.receivedApplicationContext[WatchSessionBridgeKeys.contextKey] as? Data
        let reachable = session.isReachable
        Task { @MainActor in
            isReachableToPhone = reachable
            if let data { store(data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchSessionBridgeKeys.contextKey] as? Data else { return }
        Task { @MainActor in store(data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in isReachableToPhone = reachable }
    }
}
