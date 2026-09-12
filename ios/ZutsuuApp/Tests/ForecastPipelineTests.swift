// /Users/mymac/zutsuu/ios/ZutsuuApp/Tests/ForecastPipelineTests.swift
// 予報取得 → 通知予約 → 記録 → 再予約の結合経路を、時刻と通知センターを差し替えて検証する。
// 単体テストが通っても再現していた「配信済みの再送」「保存失敗」などを結合で固定するため（レビュー）。
// 関連: Fakes.swift, ../Sources/ForecastPipeline.swift, docs/appcore-api.md §3
import Testing
import Foundation
import SwiftData
import AppCore
import KiabouUI
import RiskEngine
@testable import ZutsuuApp

@MainActor
@Suite("予報パイプラインの結合")
struct ForecastPipelineTests {
    /// 2026-03-10 09:00 UTC を「いま」とし、3 時間後に注意へ上がる予報。
    let now = Date(timeIntervalSince1970: 1_773_133_200)
    let tokyo = Coordinate(latitude: 35.68, longitude: 139.77)

    private func makeStore() throws -> CheckInStore { try makeTestStore() }

    private func makePipeline(clock: @escaping @Sendable () -> Date, center: FakeNotificationCenter,
                              riseIn hours: Double? = 3, store: CheckInStore? = nil) throws -> ForecastPipeline {
        let riseAt = hours.map { now.addingTimeInterval($0 * 3600) }
        let weather = FakeWeather { start, _ in makeForecast(from: start, hours: 110, riseAt: riseAt) }
        return ForecastPipeline(store: try store ?? makeStore(), weather: weather,
                                location: FakeLocation(result: .success(tokyo)),
                                notifications: center, defaults: isolatedDefaults("pipeline"), clock: clock)
    }

    @Test("予報を取ると事前通知が 1 件予約され、次の通知として表示される")
    func schedulesAdvanceAlert() async throws {
        let center = FakeNotificationCenter()
        let pipeline = try makePipeline(clock: { self.now }, center: center)
        await pipeline.refresh()
        #expect(pipeline.errorMessage == nil)
        #expect(pipeline.current != nil)
        let pending = await center.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .advance)
        #expect(pipeline.nextAlert?.fireDate == pending.first?.fireDate)
    }

    /// レビュー R01: 配信済みの事前通知は、記録や更新で再計算しても再予約しない。
    @Test("配信済みのエピソードは記録・更新で再送されない")
    func deliveredAlertIsNotRescheduled() async throws {
        let center = FakeNotificationCenter()
        let clock = ClockBox(now)
        let pipeline = try makePipeline(clock: { clock.now }, center: center)
        await pipeline.refresh()
        let first = try #require(await center.pending().first)

        // 発火後（対象時刻はまだ未来）。OS は配信して保留から消す。
        clock.now = first.fireDate.addingTimeInterval(60)
        center.deliver(before: clock.now)
        try await pipeline.record(HealthCheckIn(feeling: .normal))
        #expect(await center.pending().isEmpty)
        #expect(center.addedIdentifiers.count == 1)

        await pipeline.refresh()
        #expect(center.addedIdentifiers.count == 1)
        #expect(pipeline.nextAlert == nil)
    }

    /// レビュー R08: 追加に失敗した予約は「次の通知」に出ず、失敗が表示に伝わる。
    @Test("追加に失敗した予約は表示に出ず失敗が伝わる")
    func failedAdditionIsReported() async throws {
        let center = FakeNotificationCenter()
        let pipeline = try makePipeline(clock: { self.now }, center: center)
        // 1 回目で識別子を知り、2 回目で失敗させる。
        await pipeline.refresh()
        let id = try #require(await center.pending().first?.identifier)
        center.deliver(before: .distantFuture)
        center.failingIdentifiers = [id]
        // 台帳は「未配信」なので再追加を試みる → 失敗。
        try await pipeline.record(HealthCheckIn(feeling: .good))
        #expect(pipeline.notificationScheduleFailed)
        #expect(pipeline.nextAlert == nil)
    }

    @Test("通知が拒否されていれば表示に伝わり、予約しても届かないことが分かる")
    func deniedAuthorizationIsReported() async throws {
        let center = FakeNotificationCenter()
        center.status = .denied
        let pipeline = try makePipeline(clock: { self.now }, center: center)
        await pipeline.refresh()
        #expect(pipeline.notificationsAuthorized == false)
    }

    /// レビュー R09: 予報を持たないまま届いた Watch の記録も、要因付きで保存される。
    @Test("Watch の記録は予報を取り直してから要因付きで保存される")
    func watchRecordGetsFactors() async throws {
        let center = FakeNotificationCenter()
        let store = try makeStore()
        let pipeline = try makePipeline(clock: { self.now }, center: center, store: store)
        try await pipeline.record(fromWatch: WatchCheckIn(id: UUID(), date: now, feeling: "bad"))
        let observations = try store.observations()
        #expect(observations.count == 1)
        #expect(observations.first?.wasBad == true)
    }

    /// 位置が取れないとき、直近の座標で予報を続ける。
    @Test("位置取得に失敗しても直近の座標で予報を取る")
    func fallsBackToLastCoordinate() async throws {
        let center = FakeNotificationCenter()
        let defaults = isolatedDefaults("location")
        let weather = FakeWeather { start, _ in makeForecast(from: start, hours: 110, riseAt: nil) }
        let first = ForecastPipeline(store: try makeStore(), weather: weather,
                                     location: FakeLocation(result: .success(tokyo)),
                                     notifications: center, defaults: defaults, clock: { self.now })
        await first.refresh()
        #expect(first.errorMessage == nil)
        let second = ForecastPipeline(store: try makeStore(), weather: weather,
                                      location: FakeLocation(result: .failure(.unavailable)),
                                      notifications: center, defaults: defaults, clock: { self.now })
        await second.refresh()
        #expect(second.errorMessage == nil)
        #expect(second.current != nil)
    }

    @Test("現在を含まない予報は成功として公開しない")
    func seriesWithoutNowIsAnError() async throws {
        let center = FakeNotificationCenter()
        let weather = FakeWeather { start, _ in makeForecast(from: start, hours: 3, riseAt: nil) }
        let pipeline = ForecastPipeline(store: try makeStore(), weather: weather,
                                        location: FakeLocation(result: .success(tokyo)),
                                        notifications: center, defaults: isolatedDefaults("short"),
                                        clock: { self.now })
        await pipeline.refresh()
        #expect(pipeline.errorMessage != nil)
        #expect(pipeline.current == nil)
    }
}

/// テストから進められる時計。
final class ClockBox: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}
