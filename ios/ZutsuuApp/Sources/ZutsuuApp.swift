// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ZutsuuApp.swift
// アプリの入口。SwiftData コンテナと予報パイプラインを組み立て、バックグラウンド更新を登録する。
// 配線をここ 1 箇所に集め、判断は AppCore / RiskEngine に置くため。
// 関連: ForecastPipeline.swift, BackgroundRefresh.swift, docs/plans/2026-09-09-app-layer-plan2.md
import SwiftUI
import SwiftData

@main
struct ZutsuuApp: App {
    private let container: ModelContainer
    private let pipeline: ForecastPipeline

    init() {
        do {
            container = try ModelContainer(for: CheckInRecord.self)
        } catch {
            // 端末内 DB が開けない状態では体調記録の約束（保存成功時のみ完了表示）を
            // 守れない。黙って動かすより起動時に落として原因を見せる。
            fatalError("SwiftData の初期化に失敗: \(error)")
        }
        let pipeline = ForecastPipeline(store: CheckInStore(context: container.mainContext))
        self.pipeline = pipeline
        BackgroundRefresh.register(pipeline)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pipeline)
        }
        .modelContainer(container)
    }
}
