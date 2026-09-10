// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/SettingsView.swift
// 静穏時間・体質申告・通知権限の設定。
// 申告は事前分布の傾けにだけ使い（設計書 §6.5）、変更は次回の予約更新で効く。
// 関連: AppSettings.swift, SensitivityToggles.swift, ForecastPipeline.swift, EvidenceView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(ForecastPipeline.self) private var pipeline
    @AppStorage("kiabou.ambient") private var ambient = false
    @AppStorage(SettingsKey.quietEnabled) private var quietEnabled = true
    @AppStorage(SettingsKey.quietStart) private var quietStart = 22.0
    @AppStorage(SettingsKey.quietEnd) private var quietEnd = 8.5
    @State private var notificationsGranted: Bool?

    private let notifications = NotificationClient()

    var body: some View {
        NavigationStack {
            Form {
                Section("通知") {
                    if notificationsGranted == false {
                        Button("通知を許可する") {
                            Task { notificationsGranted = await notifications.requestAuthorization() }
                        }
                    } else {
                        Text(notificationsGranted == true ? "通知は許可されています" : "確認中…")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("画面のうしろを泳ぐ", isOn: $ambient)
                } header: {
                    Text("きあぼう")
                } footer: {
                    Text("ホーム画面の後ろを、きあぼうがゆっくり泳ぎます。")
                }
                Section {
                    Toggle("静穏時間", isOn: $quietEnabled)
                    if quietEnabled {
                        SlotPicker("開始", value: $quietStart)
                        SlotPicker("終了", value: $quietEnd)
                    }
                } header: {
                    Text("鳴らさない時間帯")
                } footer: {
                    Text("この時間帯に当たる通知は明けの時刻に届きます。")
                }
                Section {
                    SensitivityToggles { Task { await pipeline.refresh() } }
                } header: {
                    Text("心当たりのある条件")
                } footer: {
                    Text("わからないままで大丈夫です。記録が少ないうちの通知の目安に使うだけで、記録が増えると実際の記録のほうが優先されます。")
                }
                Section("このアプリについて") {
                    NavigationLink("スコアの根拠") { EvidenceView() }
                }
            }
            .navigationTitle("設定")
            .task { notificationsGranted = await notifications.authorizationStatus() == .authorized }
            .onChange(of: quietEnabled) { _, _ in Task { await pipeline.refresh() } }
            .onChange(of: quietStart) { _, _ in Task { await pipeline.refresh() } }
            .onChange(of: quietEnd) { _, _ in Task { await pipeline.refresh() } }
        }
    }
}

/// 30 分刻みの時刻選択。`QuietHours` の `22.0` / `8.5` 表現に合わせる。
private struct SlotPicker: View {
    let title: String
    @Binding var value: Double

    init(_ title: String, value: Binding<Double>) {
        self.title = title
        _value = value
    }

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(0..<48, id: \.self) { slot in
                let hours = Double(slot) / 2
                Text(String(format: "%02d:%02d", slot / 2, slot % 2 * 30)).tag(hours)
            }
        }
    }
}
