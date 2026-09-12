// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/WatchSessionBridge.swift
// iPhone 側の WatchConnectivity。予報の要約を Watch へ送り、Watch の記録を受け取って保存経路へ戻す。
// 記録の転送は到達保証のある transferUserInfo に限り、受信は既存の重複防止つき保存を通すため（Plan 5）。
// 関連: ForecastPipeline.swift, ../../ZutsuuKit/Sources/AppCore/WatchPayload.swift,
//       ../../ZutsuuWatch/Sources/WatchSession.swift, docs/plans/2026-09-12-watchos-plan5.md
import Foundation
import OSLog
import WatchConnectivity
import AppCore

@MainActor
final class WatchSessionBridge: NSObject {
    nonisolated static let contextKey = "context"
    nonisolated static let checkInKey = "checkIn"

    private let pipeline: ForecastPipeline
    private let logger = Logger(subsystem: "com.mintiasaikoh.zutsuu", category: "watch")

    init(pipeline: ForecastPipeline) {
        self.pipeline = pipeline
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        pipeline.watchContextSink = { [weak self] context in self?.send(context) }
    }

    private func send(_ context: WatchContext) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext([Self.contextKey: try context.encoded()])
        } catch {
            logger.error("Watch への要約送信に失敗: \(String(describing: error), privacy: .public)")
        }
    }

    private func receive(_ data: Data) {
        Task { @MainActor in
            do {
                let checkIn = try WatchCheckIn.decode(data)
                try await pipeline.record(fromWatch: checkIn)
                // 体調と記録 ID は健康情報なので公開ログに出さない（レビュー R22）。保存できた事実だけ残す。
                logger.notice("Watch の記録を保存した")
            } catch {
                logger.error("Watch の記録を保存できません: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension WatchSessionBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // 有効化後に最新の要約を送り直す。Watch アプリの再インストール直後などに空のままにしない。
        Task { @MainActor in await pipeline.refreshIfStale() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Watch を切り替えたとき。再有効化しないと新しい Watch に届かない。
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    /// sendMessage と transferUserInfo の両方を同じ経路で受ける。
    private nonisolated func handle(_ userInfo: [String: Any]) {
        // Data だけを取り出して渡す（辞書は Sendable でない）。
        guard let data = userInfo[Self.checkInKey] as? Data else {
            Logger(subsystem: "com.mintiasaikoh.zutsuu", category: "watch")
                .error("Watch からの userInfo に記録が入っていない: \(userInfo.keys.joined(separator: ","), privacy: .public)")
            return
        }
        Task { @MainActor in receive(data) }
    }
}
