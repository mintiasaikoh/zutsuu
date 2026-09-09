// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/RootView.swift
// 今日・記録・設定の 3 タブ。最後に開いたタブを記憶する。
// メイン画面（Tier 0）と体調記録を最短で行き来できるようにするため（設計書 §3, §6.1）。
// 関連: TodayView.swift, SettingsView.swift, ../../ZutsuuKit/Sources/KiabouUI/KiabouCheckInView.swift
import SwiftUI
import KiabouUI

enum AppTab: String {
    case today
    case checkIn
    case settings
}

struct RootView: View {
    @Environment(ForecastPipeline.self) private var pipeline
    /// 起動引数 `-ui.selectedTab checkIn` でも指定できる（検証用）。
    @AppStorage("ui.selectedTab") private var selectedTab = AppTab.today.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("今日", systemImage: "cloud.sun", value: AppTab.today.rawValue) {
                TodayView()
            }
            Tab("記録", systemImage: "heart.text.square", value: AppTab.checkIn.rawValue) {
                KiabouCheckInView(onRecord: pipeline.record)
            }
            Tab("設定", systemImage: "gearshape", value: AppTab.settings.rawValue) {
                SettingsView()
            }
        }
    }
}
