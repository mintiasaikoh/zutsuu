// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/TodayView.swift
// ホーム。above the fold は「今のリスク → 次の通知 → 1 タップ記録」の 3 要素だけ。
// 起動 2 秒で「今どうか・次に何が来るか」が読め、その場で記録できるようにするため（設計原則 §1.3）。
// 関連: ForecastPipeline.swift, ../../ZutsuuKit/Sources/KiabouUI/KiabouQuickCheckIn.swift, docs/plans/2026-09-09-home-dashboard-plan3.md
import SwiftUI
import ZutsuuAds
import AppCore
import KiabouUI
import RiskEngine

struct TodayView: View {
    @Environment(ForecastPipeline.self) private var pipeline
    @Environment(AdsCoordinator.self) private var ads
    @Environment(\.scenePhase) private var scenePhase
    /// 時計。毎分進めて「いま」の時間帯・時間別一覧・次の通知の表示を再評価する（レビュー R07）。
    @State private var clockTick = 0
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("kiabou.ambient") private var ambient = false

    private var palette: KiabouPalette { KiabouPalette(dim: colorScheme == .dark) }
    /// 背面遊泳モードが実際に効いているか。Reduce Motion 時はカード内表示へ戻す（§3.1）。
    private var swimsBehind: Bool { ambient && !reduceMotion }
    /// 背面遊泳時のカード地の不透明度。時間別は情報密度が低い一覧なので、
    /// きあぼうの泳ぐ場所として一段濃く透かす。
    private var cardOpacity: Double { swimsBehind ? 0.7 : 1 }
    private var hourlyOpacity: Double { swimsBehind ? 0.45 : 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    nextAlertCard
                    Card(palette: palette, backgroundOpacity: cardOpacity) {
                        KiabouQuickCheckIn(recordedDays: pipeline.recordedDays,
                                           showsStage: !swimsBehind,
                                           onRecord: pipeline.record)
                    }
                    if let swing = pipeline.swing, swing.hasAlert {
                        Card(palette: palette, title: String(localized: "寒暖差"), backgroundOpacity: cardOpacity) {
                            if swing.difference > 0 {
                                Text("昨日の最高気温より高く、差は \(Int(abs(swing.difference).rounded()))℃。")
                            } else {
                                Text("昨日の最高気温より低く、差は \(Int(abs(swing.difference).rounded()))℃。")
                            }
                        }
                    }
                    if !pipeline.upcoming.isEmpty {
                        Card(palette: palette, title: String(localized: "時間別"), backgroundOpacity: hourlyOpacity) {
                            VStack(spacing: 0) {
                                // Tier 1: 6 行目の後に 1 枠。可視域に入ってからロードする（設計書 §8.2）。
                                ForEach(Array(pipeline.upcoming.prefix(24).enumerated()), id: \.element.id) { index, risk in
                                    HourRow(risk: risk, palette: palette)
                                    if index == 5 { NativeAdCard(isEnabled: ads.isReady) }
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
            .onReceive(clock) { _ in clockTick += 1 }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await pipeline.refreshIfStale() } }
            }
        }
    }

    // MARK: - 今のリスク

    @ViewBuilder
    private var heroCard: some View {
        Card(palette: palette, backgroundOpacity: cardOpacity) {
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
                        .id(clockTick)
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
            Card(palette: palette, title: String(localized: "次の通知"), backgroundOpacity: cardOpacity) {
                if pipeline.notificationScheduleFailed {
                    Text("通知の予約に失敗しました。下に引いて更新すると、もう一度予約します。")
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if pipeline.notificationsAuthorized == false {
                    Text("通知が許可されていないため、お知らせは届きません。設定アプリから許可できます。")
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let next = pipeline.nextAlert {
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
                // Apple Weather の帰属表示: マークとリンクの両方（設計書 §9）。
                AsyncImage(url: attribution.markURL) { image in
                    image.resizable().scaledToFit().frame(height: 14)
                } placeholder: { EmptyView() }
                    .accessibilityHidden(true)
                Link("Apple Weather のデータについて", destination: attribution.legalPageURL)
            }
        }
        .font(.footnote)
        .foregroundStyle(palette.muted)
        .padding(.top, 8)
    }
}

/// 3 色 + 紙白の規律に沿ったカード。タイトルは任意。
/// `backgroundOpacity` は背面遊泳モード用 — 下げるほど後ろを泳ぐきあぼうが透ける。
private struct Card<Content: View>: View {
    let palette: KiabouPalette
    var title: String?
    var backgroundOpacity: Double = 1
    @ViewBuilder let content: Content

    init(palette: KiabouPalette, title: String? = nil, backgroundOpacity: Double = 1,
         @ViewBuilder content: () -> Content) {
        self.palette = palette
        self.title = title
        self.backgroundOpacity = backgroundOpacity
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
        .background(palette.card.opacity(backgroundOpacity),
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

/// 画面用の要因説明。通知本文と同じ実装（絶対気圧・1/3/6 時間の気圧変化を含む。レビュー R16）。
enum FactorText {
    static func summary(for risk: HourlyRisk) -> String {
        let text = AlertNotifications.factorSummary(factors: risk.assessment.factors, risk: risk)
        return text.isEmpty ? String(localized: "大きな変化はありません。") : text
    }
}
