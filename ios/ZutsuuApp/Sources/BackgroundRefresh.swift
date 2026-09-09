// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/BackgroundRefresh.swift
// BGAppRefreshTask の登録と次回予約。
// 起動していない間も予約済み通知を更新し続けるため（設計書 §4「なぜ確実なのか」）。
// 関連: ZutsuuApp.swift, ForecastPipeline.swift
import BackgroundTasks
import Foundation

enum BackgroundRefresh {
    /// Info.plist の `BGTaskSchedulerPermittedIdentifiers` と一致させること。
    static let identifier = "com.mintiasaikoh.zutsuu.refresh"

    static func register(_ pipeline: ForecastPipeline) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            scheduleNext()
            // BGTask は Sendable でないが、メソッドはスレッド安全。完了通知のためだけに
            // MainActor の Task へ持ち込む。
            let box = UncheckedSendable(task)
            let work = Task { @MainActor in
                await pipeline.refresh()
                box.value.setTaskCompleted(success: pipeline.errorMessage == nil)
            }
            task.expirationHandler = { work.cancel() }
        }
        scheduleNext()
    }

    /// 3 時間後以降。OS 都合で走らなくても、最後の起動時点で 72 時間分の
    /// 通知が予約済みなので途切れない。
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

private final class UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
