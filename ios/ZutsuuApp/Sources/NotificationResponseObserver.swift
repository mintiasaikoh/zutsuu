// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/NotificationResponseObserver.swift
// 通知タップで前面に来たことを広告側へ伝え、前面中の通知もバナーで見せる。
// 通知経由の起動を遷移カウントと App Open 広告から除外するため（設計書 §8.2）。
// 関連: AdsCoordinator.swift, NotificationClient.swift
import Foundation
import UserNotifications

final class NotificationResponseObserver: NSObject, UNUserNotificationCenterDelegate {
    private let onOpenFromNotification: @MainActor @Sendable () -> Void

    init(onOpenFromNotification: @escaping @MainActor @Sendable () -> Void) {
        self.onOpenFromNotification = onOpenFromNotification
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await onOpenFromNotification()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
