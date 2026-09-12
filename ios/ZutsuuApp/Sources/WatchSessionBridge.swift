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
    nonisolated static let ackKey = "ack"
    nonisolated static let savedKey = "saved"

    private let pipeline: ForecastPipeline
    private let logger = Logger(subsystem: "com.mintiasaikoh.zutsuu", category: "watch")
    /// 直近に送った要約。有効化後に送信だけ失敗していた場合の再送に使う（レビュー: Watch 有効化後の再送）。
    private var lastContext: WatchContext?

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
        lastContext = context
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext([Self.contextKey: try context.encoded()])
        } catch {
            logger.error("Watch への要約送信に失敗: \(String(describing: error), privacy: .public)")
        }
    }

    /// 保存して成否を返す。成功したら Watch へ ack を送る（sendMessage の返信が無い経路用）。
    private func receiveAndSave(_ data: Data) async -> Bool {
        do {
            let checkIn = try WatchCheckIn.decode(data)
            try await pipeline.record(fromWatch: checkIn)
            // 体調と記録 ID は健康情報なので公開ログに出さない（レビュー R22）。保存できた事実だけ残す。
            logger.notice("Watch の記録を保存した")
            return true
        } catch {
            logger.error("Watch の記録を保存できません: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func acknowledge(_ data: Data) {
        guard let checkIn = try? WatchCheckIn.decode(data) else { return }
        let payload = [Self.ackKey: checkIn.id.uuidString]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
        } else {
            session.transferUserInfo(payload)
        }
    }
}

extension WatchSessionBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // 有効化後に最新の要約を送り直す。手元にあればそれを、無ければ予報を取り直して送る。
        Task { @MainActor in
            if let cached = lastContext { send(cached) } else { await pipeline.refreshIfStale() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Watch を切り替えたとき。再有効化しないと新しい Watch に届かない。
        session.activate()
    }

    /// sendMessage（返信あり）: 保存してから `saved` を返す。Watch はこの返信で未確認を消す（レビュー R03）。
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[Self.checkInKey] as? Data else {
            replyHandler([Self.savedKey: false])
            return
        }
        // WatchConnectivity の返信クロージャは Sendable でない。MainActor へ運ぶために箱に入れる。
        let reply = ReplyBox(replyHandler)
        Task { @MainActor in
            let saved = await receiveAndSave(data)
            reply.handler([Self.savedKey: saved])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    /// 返信経路のない受信。保存できたら ack を送り返す。
    private nonisolated func handle(_ userInfo: [String: Any]) {
        // Data だけを取り出して渡す（辞書は Sendable でない）。
        guard let data = userInfo[Self.checkInKey] as? Data else {
            Logger(subsystem: "com.mintiasaikoh.zutsuu", category: "watch")
                .error("Watch からの userInfo に記録が入っていない: \(userInfo.keys.joined(separator: ","), privacy: .public)")
            return
        }
        Task { @MainActor in
            if await receiveAndSave(data) { acknowledge(data) }
        }
    }
}

/// `sendMessage` の返信クロージャを actor 境界越しに運ぶための箱。WatchConnectivity が
/// 別スレッドで呼ぶクロージャを MainActor 上の保存完了後に一度だけ呼ぶ用途に限る。
private final class ReplyBox: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
}
