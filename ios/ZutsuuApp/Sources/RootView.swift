// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/RootView.swift
// 初回はオンボーディング、以降は今日・記録・設定の 3 タブ。最後に開いたタブを記憶する。
// メイン画面（Tier 0）と体調記録を最短で行き来できるようにするため（設計書 §3, §6.1）。
// 関連: OnboardingView.swift, TodayView.swift, SettingsView.swift, ../../ZutsuuKit/Sources/KiabouUI/KiabouCheckInView.swift
import SwiftUI
import KiabouUI

enum AppTab: String {
    case today
    case checkIn
    case settings
}

struct RootView: View {
    @Environment(ForecastPipeline.self) private var pipeline
    @Environment(AdsCoordinator.self) private var ads
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    /// 起動引数 `-ui.selectedTab checkIn` でも指定できる（検証用）。
    @AppStorage("ui.selectedTab") private var selectedTab = AppTab.today.rawValue

    var body: some View {
        if onboardingCompleted {
            TabView(selection: $selectedTab) {
                Tab("今日", systemImage: "cloud.sun", value: AppTab.today.rawValue) {
                    TodayView()
                }
                // 記録の入口はホームに一本化。このタブは着せ替えとログの場所（Plan 3 Task 7）。
                Tab("きあぼう", systemImage: "fish", value: AppTab.checkIn.rawValue) {
                    KiabouTabView()
                }
                Tab("設定", systemImage: "gearshape", value: AppTab.settings.rawValue) {
                    SettingsView()
                }
            }
            // 広告 SDK はメイン画面の描画後に非同期で起動（設計書 §8.3）。タブ切り替えを画面遷移として数える。
            .task { ads.startAfterFirstFrame() }
            .onChange(of: selectedTab) { _, _ in ads.noteTransition() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { ads.noteForeground() } }
        } else {
            OnboardingView {
                onboardingCompleted = true
                Task { await pipeline.refresh() }
            }
        }
    }
}
