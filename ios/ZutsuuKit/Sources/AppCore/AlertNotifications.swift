// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/AlertNotifications.swift
// ScheduledAlert から通知の識別子と文面を組み立てる。
// 種別で文面を分け、事実だけを述べる制約を 1 箇所で守るため。
// 関連: ../RiskEngine/AlertScheduler.swift, docs/appcore-api.md, 設計書 §4「文面の制約」
import Foundation
import RiskEngine

/// `UNMutableNotificationContent` に流し込む前の、OS 非依存の通知内容。
public struct AlertNotificationContent: Sendable, Equatable {
    public let identifier: String
    public let fireDate: Date
    public let kind: AlertKind
    public let targetDate: Date
    public let title: String
    public let body: String

    public init(identifier: String, fireDate: Date, kind: AlertKind, targetDate: Date,
                title: String, body: String) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.kind = kind
        self.targetDate = targetDate
        self.title = title
        self.body = body
    }
}

public enum AlertNotifications {
    /// 種別と入口時刻から決定的に作る。同じエピソードは再計算しても同じ識別子になり、
    /// `NotificationReconciler` が「同じ予約」と判定して付け替えを起こさない。
    public static func identifier(for alert: ScheduledAlert) -> String {
        let kind = alert.kind == .advance ? "advance" : "wakeup"
        return "zutsuu.alert.\(kind).\(Int(alert.targetDate.timeIntervalSince1970))"
    }

    /// 文面は事実のみ。「睡眠中に気圧が 8hPa 下がりました」は可、
    /// 「睡眠中に影響を受けました」は不可（設計書 §4）。予測・診断の語も使わない（§9）。
    ///
    /// 数値は入口時刻の `HourlyRisk` から取る（`ScheduledAlert` は点数しか持たない）。
    /// 入口が `risks` に見つからなければ、点数だけから数値なしの要因名を並べる。
    /// 文面は日本語で確定させる段階であり、ローカライズは Plan 2 Part B 以降。
    public static func content(for alert: ScheduledAlert, risks: [HourlyRisk],
                               calendar: Calendar) -> AlertNotificationContent {
        let risk = risks.first { $0.point.date == alert.targetDate }
        let time = timeText(alert.targetDate, calendar: calendar)
        let level = alert.targetLevel.displayName
        let summary = factorSummary(factors: alert.assessment.factors, risk: risk)

        let title: String
        let body: String
        switch alert.kind {
        case .advance:
            title = "\(time) 頃から\(level)"
            body = summary.isEmpty ? "対策するなら今のうちに。" : "\(summary)。対策するなら今のうちに。"
        case .wakeUp:
            title = alert.assessment.factors.pressure > 0
                ? "睡眠中に気圧が変化しました"
                : "睡眠中に\(level)の条件になりました"
            body = summary.isEmpty ? "\(time) 頃から\(level)。" : "\(time) 頃から\(level)。\(summary)。"
        }
        return AlertNotificationContent(identifier: identifier(for: alert), fireDate: alert.fireDate,
                                        kind: alert.kind, targetDate: alert.targetDate,
                                        title: title, body: body)
    }

    private static func timeText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    /// 点数が付いた要因だけを、数値があれば数値付きで並べる。
    static func factorSummary(factors: RiskFactors, risk: HourlyRisk?) -> String {
        var parts: [String] = []
        if factors.pressureChange > 0 {
            parts.append(pressureText(risk?.pressureChanges) ?? "気圧の変化")
        }
        if factors.pressureBaseline > 0 {
            parts.append("この土地としては低い気圧")
        }
        if factors.humidity > 0 {
            parts.append(risk.map { "湿度\(Int($0.point.humidity.rounded()))%" } ?? "高い湿度")
        }
        if factors.precipitation > 0 {
            parts.append(risk.map { "降水確率\(Int($0.point.precipitationChance.rounded()))%" }
                         ?? "降水の可能性")
        }
        if factors.temperature > 0 {
            parts.append("気温の急な変化")
        }
        return parts.joined(separator: "、")
    }

    /// 3 つの窓のうち変化量が最も大きいものを「N時間で MhPa 低下/上昇」にする。
    private static func pressureText(_ changes: PressureChanges?) -> String? {
        guard let changes else { return nil }
        let windows = [(1, changes.oneHour), (3, changes.threeHour), (6, changes.sixHour)]
        guard let (hours, change) = windows.max(by: { abs($0.1) < abs($1.1) }),
              abs(change).rounded() >= 1 else { return nil }
        return "\(hours)時間で\(Int(abs(change).rounded()))hPa\(change < 0 ? "低下" : "上昇")"
    }
}

extension RiskLevel {
    /// 通知文面用の日本語名。ローカライズ前の暫定。
    public var displayName: String {
        switch self {
        case .calm: "安心"
        case .slight: "やや注意"
        case .caution: "注意"
        case .danger: "危険"
        }
    }
}
