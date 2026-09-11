// /Users/mymac/zutsuu/ios/ZutsuuWatch/Sources/ZutsuuWatchApp.swift
// Watch アプリの入口。iPhone からの要約を受ける WatchSession を組み立てる。
// Watch は予報を取らず、表示と 1 タップ記録だけを担う（Plan 5、設計書 §7.2）ため。
// 関連: WatchRootView.swift, WatchSession.swift, ../../ZutsuuWatchWidget/Sources/ComplicationWidget.swift
import SwiftUI

@main
struct ZutsuuWatchApp: App {
    @State private var session = WatchSession()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
        }
    }
}
