// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/TodayView.swift
// 現在のリスクと今後の時間別リスク、寒暖差、Apple Weather の帰属表示。
// 起動して即座にリスクが読める Tier 0 画面（設計書 §1「軽さ」、§8 広告なし）のため。
// 関連: ForecastPipeline.swift, ../../ZutsuuKit/Sources/AppCore/AlertNotifications.swift
import SwiftUI
import AppCore
import RiskEngine

struct TodayView: View {
    @Environment(ForecastPipeline.self) private var pipeline

    var body: some View {
        NavigationStack {
            List {
                currentSection
                if let swing = pipeline.swing, swing.hasAlert {
                    Section("寒暖差") {
                        Text("昨日の最高気温より \(swing.difference > 0 ? "高く" : "低く")、差は \(Int(abs(swing.difference).rounded()))℃。")
                    }
                }
                if !pipeline.upcoming.isEmpty {
                    Section("時間別") {
                        ForEach(pipeline.upcoming.prefix(24)) { risk in
                            HourRow(risk: risk)
                        }
                    }
                }
                if let attribution = pipeline.attribution {
                    Section {
                        Link("Apple Weather のデータについて", destination: attribution.legalPageURL)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("今日")
            .refreshable { await pipeline.refresh() }
            .task { await pipeline.refreshIfStale() }
            .overlay {
                if pipeline.risks.isEmpty && pipeline.isRefreshing {
                    ProgressView("予報を取得中…")
                }
            }
        }
    }

    @ViewBuilder
    private var currentSection: some View {
        Section {
            if let current = pipeline.current {
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.assessment.level.displayName)
                        .font(.largeTitle.weight(.bold))
                    Text("\(current.assessment.score)pt / 18pt")
                        .foregroundStyle(.secondary)
                    Text(FactorText.summary(for: current))
                        .font(.body)
                }
                .padding(.vertical, 4)
            } else if let error = pipeline.errorMessage {
                Text(error).foregroundStyle(.secondary)
            } else if !pipeline.isRefreshing {
                Text("予報を取得すると、ここに現在のリスクが表示されます。")
                    .foregroundStyle(.secondary)
            }
            if let updated = pipeline.lastUpdated {
                Text("更新 \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HourRow: View {
    let risk: HourlyRisk

    var body: some View {
        HStack {
            Text(risk.point.date.formatted(.dateTime.hour().minute()))
                .monospacedDigit()
            Spacer()
            Text("\(Int(risk.point.pressure.rounded())) hPa")
                .foregroundStyle(.secondary).monospacedDigit()
            Text(risk.assessment.level.displayName)
                .frame(minWidth: 64, alignment: .trailing)
                .foregroundStyle(risk.assessment.level >= .caution ? .primary : .secondary)
        }
        .font(.subheadline)
    }
}

/// 画面用の要因説明。通知文面と同じ言い回しにするため AppCore の要約に寄せる。
enum FactorText {
    static func summary(for risk: HourlyRisk) -> String {
        let factors = risk.assessment.factors
        var parts: [String] = []
        let change = risk.pressureChanges.threeHour
        if factors.pressureChange > 0, abs(change).rounded() >= 1 {
            parts.append("3時間で\(Int(abs(change).rounded()))hPa\(change < 0 ? "低下" : "上昇")")
        }
        if factors.humidity > 0 { parts.append("湿度\(Int(risk.point.humidity.rounded()))%") }
        if factors.precipitation > 0 {
            parts.append("降水確率\(Int(risk.point.precipitationChance.rounded()))%")
        }
        if factors.temperature > 0 { parts.append("気温の急な変化") }
        return parts.isEmpty ? "大きな変化はありません。" : parts.joined(separator: "、")
    }
}
