// /Users/mymac/zutsuu/ios/ZutsuuWatchWidget/Sources/ComplicationWidget.swift
// 文字盤コンプリケーション。リスクレベル名だけを出す（設計書 §7.2 の線引き）。
// 毎日目に入る場所に Tier 0 相当の情報だけを置き、詳細は iPhone に残すため。
// 関連: ../../ZutsuuWatch/Sources/WatchSession.swift, ../../ZutsuuKit/Sources/AppCore/WatchPayload.swift
import SwiftUI
import WidgetKit
import AppCore
import RiskEngine

struct LevelEntry: TimelineEntry {
    let date: Date
    let level: RiskLevel?
    let nextAlertTitle: String?
}

struct LevelProvider: TimelineProvider {
    private static let appGroup = "group.com.mintiasaikoh.zutsuu"
    private static let contextKey = "watch.context"

    private func context() -> WatchContext? {
        guard let data = UserDefaults(suiteName: Self.appGroup)?.data(forKey: Self.contextKey) else { return nil }
        return try? WatchContext.decode(data)
    }

    func placeholder(in context: Context) -> LevelEntry {
        LevelEntry(date: Date(), level: .calm, nextAlertTitle: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LevelEntry) -> Void) {
        let summary = self.context()
        completion(LevelEntry(date: Date(), level: summary?.level(at: Date()), nextAlertTitle: summary?.nextAlertTitle))
    }

    /// 要約の毎時レベルをそのままタイムラインにする。要約が古くなる時刻で「—」の項目を足し、
    /// 古い予報を今のものとして出し続けない。
    func getTimeline(in context: Context, completion: @escaping (Timeline<LevelEntry>) -> Void) {
        guard let summary = self.context() else {
            completion(Timeline(entries: [LevelEntry(date: Date(), level: nil, nextAlertTitle: nil)], policy: .never))
            return
        }
        var entries = summary.hourly
            .filter { $0.date.timeIntervalSince(summary.updatedAt) < WatchContext.staleAfter }
            .map { LevelEntry(date: $0.date, level: $0.level, nextAlertTitle: summary.nextAlertTitle) }
        let stale = summary.updatedAt.addingTimeInterval(WatchContext.staleAfter)
        entries.append(LevelEntry(date: stale, level: nil, nextAlertTitle: nil))
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LevelEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("きあぼう").font(.caption2).foregroundStyle(.secondary)
                Text(entry.level?.displayName ?? "—").font(.headline)
                if let next = entry.nextAlertTitle { Text(next).font(.caption2).lineLimit(1) }
            }
        default:
            Text(entry.level.map(Self.short) ?? "—").font(.headline)
        }
    }

    /// 円形の小さな枠に収まる 2 文字。
    private static func short(_ level: RiskLevel) -> String {
        switch level {
        case .calm: String(localized: "安心")
        case .slight: String(localized: "やや")
        case .caution: String(localized: "注意")
        case .danger: String(localized: "危険")
        }
    }
}

@main
struct ComplicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZutsuuComplication", provider: LevelProvider()) { entry in
            ComplicationView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("いまのリスク")
        .description("気圧などから見た、いまの体調リスクの段階。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
