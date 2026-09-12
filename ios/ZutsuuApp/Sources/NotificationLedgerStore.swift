// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/NotificationLedgerStore.swift
// 通知台帳（NotificationLedger）の永続化。UserDefaults に JSON で置く。
// 配信済みエピソードの記憶をアプリの再起動をまたいで保つため（レビュー R01）。
// 関連: ForecastPipeline.swift, ../../ZutsuuKit/Sources/AppCore/NotificationLedger.swift
import Foundation
import AppCore

struct NotificationLedgerStore {
    static let key = "notifications.ledger"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NotificationLedger {
        guard let data = defaults.data(forKey: Self.key),
              let ledger = try? JSONDecoder().decode(NotificationLedger.self, from: data) else {
            return NotificationLedger()
        }
        return ledger
    }

    func save(_ ledger: NotificationLedger) {
        defaults.set(try? JSONEncoder().encode(ledger), forKey: Self.key)
    }
}
