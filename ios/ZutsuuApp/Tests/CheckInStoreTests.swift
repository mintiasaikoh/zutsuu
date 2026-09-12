// /Users/mymac/zutsuu/ios/ZutsuuApp/Tests/CheckInStoreTests.swift
// 体調記録の保存の契約（重複防止・後からの要因付け）を SwiftData のインメモリで検証する。
// 保存経路の不具合は静かに記録を失うため、結合で固定する（レビュー）。
// 関連: ../Sources/CheckInStore.swift, docs/kiabou-integration.md §2.2
import Testing
import Foundation
import SwiftData
import KiabouUI
import RiskEngine
@testable import ZutsuuApp

extension SharedStoreSuites {
@MainActor
@Suite("体調記録の保存")
struct CheckInStoreTests {
    private func makeStore() throws -> CheckInStore { try makeTestStore() }

    @Test("同じ id の再試行は 1 件しか保存されない")
    func duplicateIDIsSavedOnce() throws {
        let store = try makeStore()
        let checkIn = HealthCheckIn(feeling: .bad)
        try store.save(checkIn, risk: nil)
        try store.save(checkIn, risk: nil)
        #expect(try store.count() == 1)
    }

    @Test("要因なしで保存した記録に後から要因を付けられる")
    func backfillAddsFactors() throws {
        let store = try makeStore()
        let date = Date(timeIntervalSince1970: 1_773_133_200)
        try store.save(HealthCheckIn(date: date, feeling: .bad), risk: nil)
        #expect(try store.observations().isEmpty)

        let point = WeatherPoint(date: date, pressure: 1000, temperature: 20, humidity: 90,
                                 precipitationChance: 80, precipitationAmount: 0)
        let risk = HourlyRisk(point: point,
                              assessment: RiskAssessment(level: .caution, score: 4,
                                                         factors: RiskFactors(pressureChange: 0, pressureBaseline: 0,
                                                                              humidity: 2, precipitation: 2, temperature: 0)),
                              pressureChanges: PressureChanges(oneHour: 0, threeHour: -2, sixHour: -4))
        let updated = try store.backfillFactors { $0 == date ? risk : nil }
        #expect(updated == 1)
        let observations = try store.observations()
        #expect(observations.count == 1)
        #expect(observations.first?.factors.humidity == 2)
        // 2 回目は対象がない。
        #expect(try store.backfillFactors { _ in risk } == 0)
    }
}
}
