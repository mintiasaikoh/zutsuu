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
    /// iPhone が「保存した」と応答していない記録。再送の対象（レビュー R03）。
    private(set) var unacknowledged: [WatchCheckIn] = WatchSession.loadQueue()
    private static let queueKey = "watch.unacknowledged"
    private static let queueLimit = 50

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 現在時刻のレベル。要約が無い・古い場合は nil。
    var currentLevel: RiskLevel? { context?.level(at: Date()) }

    /// 記録は iPhone が**保存した**と応答するまで「未確認」として持ち続け、再送する（レビュー R03）。
    /// 届く範囲なら sendMessage の返信で確認し、届かなければ transferUserInfo で送って
    /// iPhone からの ack（`ack` キー）を待つ。両方届いても iPhone 側は同じ id を重複保存しない。
    func record(_ feeling: HealthFeeling) {
        let checkIn = WatchCheckIn(id: UUID(), date: Date(), feeling: feeling.rawValue)
        unacknowledged.append(checkIn)
        if unacknowledged.count > Self.queueLimit { unacknowledged.removeFirst() }
        Self.saveQueue(unacknowledged)
        lastRecorded = feeling
        flush()
    }

    /// 未確認の記録を全部送り直す。起動・到達可能になったとき・記録直後に呼ぶ。
    func flush() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for checkIn in unacknowledged {
            guard let data = try? checkIn.encoded() else { continue }
            let payload: [String: Data] = [WatchSessionBridgeKeys.checkInKey: data]
            let id = checkIn.id
            if session.isReachable {
                // WatchConnectivity は返信・エラーを別キューで呼ぶ。MainActor 隔離のクロージャを渡すと
                // 実行時の隔離チェックで落ちる（実測）ので、@Sendable で非隔離にし、MainActor へは Task で戻る。
                session.sendMessage(payload, replyHandler: { @Sendable [weak self] reply in
                    guard reply[WatchSessionBridgeKeys.savedKey] as? Bool == true else { return }
                    Task { @MainActor in self?.acknowledge(id) }
                }, errorHandler: { @Sendable _ in
                    WCSession.default.transferUserInfo(payload)
                })
            } else {
                session.transferUserInfo(payload)
            }
        }
    }

    private func acknowledge(_ id: UUID) {
        unacknowledged.removeAll { $0.id == id }
        Self.saveQueue(unacknowledged)
    }

    private static func loadQueue() -> [WatchCheckIn] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([WatchCheckIn].self, from: data)) ?? []
    }

    private static func saveQueue(_ queue: [WatchCheckIn]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(queue), forKey: queueKey)
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
    /// iPhone → Watch: 保存できた記録の id（UUID 文字列）。
    static let ackKey = "ack"
    /// sendMessage の返信: 保存できたか。
    static let savedKey = "saved"
    /// iPhone → Watch: 未確認の記録を送り直す合図。
    static let resendKey = "resend"
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
            flush()
        }
    }

    /// iPhone が transferUserInfo で届いた記録を保存したときの ack。
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo[WatchSessionBridgeKeys.ackKey] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in acknowledge(id) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message[WatchSessionBridgeKeys.resendKey] as? Bool == true {
            Task { @MainActor in flush() }
            return
        }
        guard let raw = message[WatchSessionBridgeKeys.ackKey] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in acknowledge(id) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchSessionBridgeKeys.contextKey] as? Data else { return }
        Task { @MainActor in store(data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachableToPhone = reachable
            if reachable { flush() }
        }
    }
}
