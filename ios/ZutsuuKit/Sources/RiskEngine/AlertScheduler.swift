import Foundation

/// 通知を出さない時間帯。端末ローカル時刻の壁時計で判定する。
/// 既定は 22:00〜08:30（設計書 §4）。ユーザーが変更できる。
public struct QuietHours: Sendable, Equatable {
    /// 開始時刻（22.0 = 22:00）
    public let start: Double
    /// 終了時刻（8.5 = 08:30）。この時刻ちょうどは静穏時間に含まない。
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// `start > end` のときは日付をまたぐ区間として扱う。
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
    }
}

/// 予約する 1 件のローカル通知。
/// アプリ層はこの `fireDate` をそのまま `UNNotificationRequest` のトリガに渡す。
public struct ScheduledAlert: Sendable, Equatable {
    /// 通知を発火させる時刻。
    public let fireDate: Date
    /// リスクが上がる時刻。通知本文で「何時から」を示すために使う。
    public let targetDate: Date
    /// その時刻に到達するリスクレベル。
    public let targetLevel: RiskLevel

    public init(fireDate: Date, targetDate: Date, targetLevel: RiskLevel) {
        self.fireDate = fireDate
        self.targetDate = targetDate
        self.targetLevel = targetLevel
    }
}

/// リスク曲線から通知予約時刻を算出する。
/// サーバーを持たず端末上で先に予約する設計（設計書 §4）の中核。
public struct AlertScheduler: Sendable {
    /// 症状発現の何分前に通知するか。設計書 §4 の「1〜2時間前」の中央値。
    public static let leadTime: TimeInterval = 90 * 60

    /// これ以上のレベルへ上がる場合のみ通知する。
    public static let threshold: RiskLevel = .caution

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// リスク曲線から通知予約のリストを作る。
    /// 「レベルが上がった瞬間」だけを拾う。高いレベルが続く間は再通知しない。
    public func schedule(_ risks: [HourlyRisk], quietHours: QuietHours?) -> [ScheduledAlert] {
        guard risks.count > 1 else { return [] }

        var alerts: [ScheduledAlert] = []
        for index in 1..<risks.count {
            let previous = risks[index - 1].assessment.level
            let current = risks[index].assessment.level

            guard current > previous, current >= Self.threshold else { continue }

            let targetDate = risks[index].point.date
            let fireDate = targetDate.addingTimeInterval(-Self.leadTime)

            if let quietHours, quietHours.contains(fireDate, calendar: calendar) { continue }

            alerts.append(ScheduledAlert(fireDate: fireDate,
                                         targetDate: targetDate,
                                         targetLevel: current))
        }
        return alerts
    }
}
