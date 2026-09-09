// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/NotificationClient.swift
// UNUserNotificationCenter との入出力。保留分の読み戻しと ReconcilePlan の適用。
// 再スケジュールを必ず NotificationReconciler 経由にするため（appcore-api.md §3.3）。
// 関連: ../../ZutsuuKit/Sources/AppCore/NotificationReconciler.swift, AlertNotifications.swift
import Foundation
import UserNotifications
import AppCore
import RiskEngine

struct NotificationClient: Sendable {
    private enum Key {
        static let kind = "kind"
        static let targetDate = "targetDate"
        static let fireDate = "fireDate"
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 保留中の予約を `PendingAlert` に復元する。`userInfo` が欠けた古い予約は
    /// 復元できないので対象外にする（reconcile は「同じ識別子」以外を取り消すため、
    /// 次の予約更新で自然に消える）。
    func pending() async -> [PendingAlert] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            let info = request.content.userInfo
            guard let kindName = info[Key.kind] as? String,
                  let kind = Self.kind(named: kindName),
                  let target = info[Key.targetDate] as? Double,
                  let fire = info[Key.fireDate] as? Double else { return nil }
            return PendingAlert(identifier: request.identifier,
                                fireDate: Date(timeIntervalSince1970: fire),
                                kind: kind,
                                targetDate: Date(timeIntervalSince1970: target))
        }
    }

    func apply(_ plan: ReconcilePlan, risks: [HourlyRisk], calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        if !plan.cancel.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: plan.cancel)
        }
        for alert in plan.add {
            let content = AlertNotifications.content(for: alert, risks: risks, calendar: calendar)
            let notification = UNMutableNotificationContent()
            notification.title = content.title
            notification.body = content.body
            notification.sound = .default
            notification.userInfo = [
                Key.kind: Self.name(of: content.kind),
                Key.targetDate: content.targetDate.timeIntervalSince1970,
                Key.fireDate: content.fireDate.timeIntervalSince1970,
            ]
            // 発火時刻は AlertScheduler が「必ず now より後」を保証している。
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: content.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: content.identifier,
                                                        content: notification, trigger: trigger))
        }
    }

    private static func name(of kind: AlertKind) -> String {
        kind == .advance ? "advance" : "wakeUp"
    }

    private static func kind(named name: String) -> AlertKind? {
        switch name {
        case "advance": .advance
        case "wakeUp": .wakeUp
        default: nil
        }
    }
}
