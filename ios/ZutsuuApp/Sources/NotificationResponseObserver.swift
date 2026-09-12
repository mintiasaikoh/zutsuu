// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/NotificationResponseObserver.swift
// 前面にいる間も通知をバナーで見せるための UNUserNotificationCenter デリゲート。
// 前面中は既定で通知が表示されないため、起動中に発火した予約が見えなくなるのを防ぐ。
// 関連: NotificationClient.swift, ForecastPipeline.swift
import Foundation
import UserNotifications

final class NotificationResponseObserver: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
