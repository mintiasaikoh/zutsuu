// /Users/mymac/zutsuu/ios/ZutsuuApp/Tests/Fakes.swift
// 結合テスト用の差し替え: 予報・位置・通知センター。
// 時刻・通知センター・保存を差し替えられる境界を作り、失敗と再実行を再現するため（レビュー: 結合テスト）。
// 関連: ForecastPipelineTests.swift, ../Sources/ForecastPipeline.swift
import Testing
import Foundation
import SwiftData
import UserNotifications
import AppCore
import RiskEngine
@testable import ZutsuuApp

struct FakeWeather: WeatherProviding {
    let points: @Sendable (Date, Date) -> [WeatherPoint]
    func hourly(at coordinate: Coordinate, from start: Date, to end: Date) async throws -> [WeatherPoint] {
        points(start, end)
    }
    func attribution() async throws -> WeatherAttribution {
        WeatherAttribution(legalPageURL: URL(string: "https://example.invalid/legal")!,
                           markURL: URL(string: "https://example.invalid/mark")!)
    }
}

struct FakeLocation: LocationProviding {
    let result: Result<Coordinate, LocationError>
    @MainActor func current() async throws -> Coordinate { try result.get() }
}

/// 通知センターの代わり。追加した予約を保持し、`deliver(before:)` で OS の配信を模倣して保留から消す。
final class FakeNotificationCenter: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [PendingAlert] = []
    var status: UNAuthorizationStatus = .authorized
    var failingIdentifiers: Set<String> = []
    private(set) var addedIdentifiers: [String] = []

    func requestAuthorization() async -> Bool { status == .authorized }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func pending() async -> [PendingAlert] { lock.withLock { requests } }

    func apply(cancel: [String], add: [ScheduledAlert], risks: [HourlyRisk], calendar: Calendar) async -> Set<String> {
        lock.withLock {
            requests.removeAll { cancel.contains($0.identifier) }
            var failed = Set<String>()
            for alert in add {
                let id = AlertNotifications.identifier(for: alert)
                if failingIdentifiers.contains(id) { failed.insert(id); continue }
                addedIdentifiers.append(id)
                requests.append(PendingAlert(identifier: id, fireDate: alert.fireDate,
                                             kind: alert.kind, targetDate: alert.targetDate))
            }
            return failed
        }
    }

    /// 発火時刻が `date` 以前の予約を配信済みとして消す（OS の挙動）。
    func deliver(before date: Date) {
        lock.withLock { requests.removeAll { $0.fireDate <= date } }
    }
}

/// 毎時の予報。`riseAt` の時刻から 3 時間、湿度 90% + 降水確率 80% で「注意」（4pt）に上げる。
func makeForecast(from start: Date, hours: Int, riseAt: Date?) -> [WeatherPoint] {
    (0..<hours).map { hour in
        let date = start.addingTimeInterval(TimeInterval(hour) * 3600)
        let stormy = riseAt.map { date >= $0 && date < $0.addingTimeInterval(3 * 3600) } ?? false
        return WeatherPoint(date: date, pressure: 1013, temperature: 20,
                            humidity: stormy ? 90 : 50, precipitationChance: stormy ? 80 : 10,
                            precipitationAmount: 0)
    }
}

/// 共有コンテナを使うスイートの親。並列に走ると別テストの「記録を空にする」が交差するので直列にする
/// （`.serialized` は入れ子のスイートにも効く）。
@Suite(.serialized) struct SharedStoreSuites {}

/// アプリと同じ（インメモリの）コンテナに新しいコンテキストを作り、記録を空にして返す。
@MainActor
func makeTestStore() throws -> CheckInStore {
    guard let container = ZutsuuApp.sharedContainer else {
        throw NSError(domain: "tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "テスト用コンテナがない"])
    }
    let context = ModelContext(container)
    try context.delete(model: CheckInRecord.self)
    try context.save()
    return CheckInStore(context: context)
}

func isolatedDefaults(_ name: String) -> UserDefaults {
    let suite = "test.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
