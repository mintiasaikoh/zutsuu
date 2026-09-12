// /Users/mymac/zutsuu/ios/ZutsuuWatch/Sources/WatchRootView.swift
// Watch の唯一の画面。いまのレベルと 3 つの記録ボタン。
// 起動して 1 タップで記録が終わる動線を Watch にも置くため（設計書 §10 v1.0）。
// 関連: WatchSession.swift, ../../ZutsuuKit/Sources/KiabouUI/HealthCheckIn.swift
import SwiftUI
import AppCore
import KiabouUI
import RiskEngine

struct WatchRootView: View {
    @Environment(WatchSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                levelHeader
                Text("いまの調子は？").font(.footnote).foregroundStyle(.secondary)
                ForEach(HealthFeeling.allCases, id: \.self) { feeling in
                    Button(feeling.label) { session.record(feeling) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(String(localized: "いまの調子は\(feeling.label)。記録する"))
                }
                if let recorded = session.lastRecorded {
                    if session.unacknowledged.isEmpty {
                        Text("「\(recorded.label)」を iPhone に保存したよ。")
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("「\(recorded.label)」を iPhone へ送っています…（未保存 \(session.unacknowledged.count) 件）")
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { session.flush() } }
    }

    @ViewBuilder
    private var levelHeader: some View {
        if let level = session.currentLevel {
            Text("いま").font(.caption2).foregroundStyle(.secondary)
            Text(level.displayName).font(.title3.weight(.semibold))
            if let next = session.context?.nextAlertTitle {
                Text(next).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } else {
            Text("iPhone で予報を開くと、ここに今のリスクが出ます。")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}
