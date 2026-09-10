// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/TodayView.swift
// ホーム。above the fold は「今のリスク → 次の通知 → 1 タップ記録」の 3 要素だけ。
// 起動 2 秒で「今どうか・次に何が来るか」が読め、その場で記録できるようにするため（設計原則 §1.3）。
// 関連: ForecastPipeline.swift, ../../ZutsuuKit/Sources/KiabouUI/KiabouQuickCheckIn.swift, docs/plans/2026-09-09-home-dashboard-plan3.md
import SwiftUI
import AppCore
import KiabouUI
import RiskEngine

struct TodayView: View {
    @Environment(ForecastPipeline.self) private var pipeline
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("kiabou.ambient") private var ambient = false

    private var palette: KiabouPalette { KiabouPalette(dim: colorScheme == .dark) }
    /// 背面遊泳モードが実際に効いているか。Reduce Motion 時はカード内表示へ戻す（§3.1）。
    private var swimsBehind: Bool { ambient && !reduceMotion }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    nextAlertCard
                    Card(palette: palette, translucent: swimsBehind) {
                        KiabouQuickCheckIn(recordedDays: pipeline.recordedDays,
                                           showsStage: !swimsBehind,
                                           onRecord: pipeline.record)
                    }
                    if let swing = pipeline.swing, swing.hasAlert {
                        Card(palette: palette, title: "寒暖差", translucent: swimsBehind) {
                            Text("昨日の最高気温より \(swing.difference > 0 ? "高く" : "低く")、差は \(Int(abs(swing.difference).rounded()))℃。")
                        }
                    }
                    if !pipeline.upcoming.isEmpty {
                        Card(palette: palette, title: "時間別", translucent: swimsBehind) {
                            VStack(spacing: 0) {
                                ForEach(pipeline.upcoming.prefix(24)) { risk in
                                    HourRow(risk: risk, palette: palette)
                                }
                            }
                        }
                    }
                    footer
                }
                .padding(16)
            }
            .background {
                if swimsBehind {
                    ZStack {
                        palette.page
                        KiabouAmbientBackdrop()
                    }
                    .ignoresSafeArea()
                } else {
                    palette.page.ignoresSafeArea()
                }
            }
            .foregroundStyle(palette.ink)
            .tint(palette.primary)
            .navigationTitle("今日")
            .refreshable { await pipeline.refresh() }
            .task { await pipeline.refreshIfStale() }
        }
    }

    // MARK: - 今のリスク

    @ViewBuilder
    private var heroCard: some View {
        Card(palette: palette, translucent: swimsBehind) {
            heroContent
        }
    }

    @ViewBuilder
    private var heroContent: some View {
        Group {
            if let current = pipeline.current {
                VStack(alignment: .leading, spacing: 8) {
                    Text("いま").font(.subheadline).foregroundStyle(palette.muted)
                    Text(current.assessment.level.displayName)
                        .font(.system(size: 44, weight: .bold))
                    Text("\(current.assessment.score) / 18 pt")
                        .font(.body.monospacedDigit()).foregroundStyle(palette.muted)
                    Text(FactorText.summary(for: current))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if pipeline.isRefreshing {
                ProgressView("予報を取得中…").frame(maxWidth: .infinity)
            } else if let error = pipeline.errorMessage {
                Text(error).foregroundStyle(palette.muted)
            } else {
                Text("予報を取得すると、ここに現在のリスクが表示されます。")
                    .foregroundStyle(palette.muted)
            }
        }
    }

    // MARK: - 次の通知

    @ViewBuilder
    private var nextAlertCard: some View {
        if pipeline.current != nil {
            Card(palette: palette, title: "次の通知", translucent: swimsBehind) {
                if let next = pipeline.nextAlert {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(next.title).font(.title3.weight(.semibold))
                        Text(next.body).foregroundStyle(palette.muted)
                        Text("\(next.fireDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())) に通知")
                            .font(.footnote.monospacedDigit()).foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("72 時間以内に通知の予定はありません。")
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 帰属・更新時刻

    private var footer: some View {
        VStack(spacing: 6) {
            if let updated = pipeline.lastUpdated {
                Text("更新 \(updated.formatted(date: .omitted, time: .shortened))")
            }
            if let attribution = pipeline.attribution {
                Link("Apple Weather のデータについて", destination: attribution.legalPageURL)
            }
        }
        .font(.footnote)
        .foregroundStyle(palette.muted)
        .padding(.top, 8)
    }
}

/// 3 色 + 紙白の規律に沿ったカード。タイトルは任意。
/// `translucent` は背面遊泳モード用 — 後ろを泳ぐきあぼうが透けて見える。
private struct Card<Content: View>: View {
    let palette: KiabouPalette
    var title: String?
    var translucent = false
    @ViewBuilder let content: Content

    init(palette: KiabouPalette, title: String? = nil, translucent: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.palette = palette
        self.title = title
        self.translucent = translucent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.muted)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card.opacity(translucent ? 0.82 : 1),
                    in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct HourRow: View {
    let risk: HourlyRisk
    let palette: KiabouPalette

    var body: some View {
        HStack {
            Text(risk.point.date.formatted(.dateTime.hour().minute()))
                .monospacedDigit()
            Spacer()
            Text("\(Int(risk.point.pressure.rounded())) hPa")
                .foregroundStyle(palette.muted).monospacedDigit()
            Text(risk.assessment.level.displayName)
                .frame(minWidth: 64, alignment: .trailing)
                .foregroundStyle(risk.assessment.level >= .caution ? palette.ink : palette.muted)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }
}

/// 画面用の要因説明。通知文面と同じ言い回しにする。
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
