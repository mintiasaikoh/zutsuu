// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/CheckInStore.swift
// 体調記録を SwiftData に保存し、学習用の観測に変換する。
// 同じ ID の再試行を重複保存しない契約（kiabou-integration.md §2.2）を守るため。
// 関連: ForecastPipeline.swift, ../../ZutsuuKit/Sources/PersonalRisk/PersonalRiskModel.swift
import Foundation
import SwiftData
import KiabouUI
import PersonalRisk
import RiskEngine

@Model
final class CheckInRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// `HealthFeeling.rawValue`。保存キーなので enum を直接持たない。
    var feeling: String
    /// 記録時点の要因点数が取れたか。予報未取得のまま記録した場合は false。
    var hasFactors: Bool
    var pressureChange: Int
    var pressureBaseline: Int
    var humidity: Int
    var precipitation: Int
    var temperature: Int

    init(checkIn: HealthCheckIn, factors: RiskFactors?) {
        id = checkIn.id
        date = checkIn.date
        feeling = checkIn.feeling.rawValue
        hasFactors = factors != nil
        pressureChange = factors?.pressureChange ?? 0
        pressureBaseline = factors?.pressureBaseline ?? 0
        humidity = factors?.humidity ?? 0
        precipitation = factors?.precipitation ?? 0
        temperature = factors?.temperature ?? 0
    }
}

@MainActor
final class CheckInStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 同じ ID が既にあれば何もしない（保存結果が不明な再試行への備え）。
    func save(_ checkIn: HealthCheckIn, factors: RiskFactors?) throws {
        let id = checkIn.id
        var descriptor = FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if try context.fetchCount(descriptor) > 0 { return }
        context.insert(CheckInRecord(checkIn: checkIn, factors: factors))
        try context.save()
    }

    /// 要因付きの記録だけを学習に使う。
    func observations() throws -> [SymptomObservation] {
        let descriptor = FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.hasFactors })
        return try context.fetch(descriptor).map { record in
            SymptomObservation(
                factors: RiskFactors(pressureChange: record.pressureChange,
                                     pressureBaseline: record.pressureBaseline,
                                     humidity: record.humidity,
                                     precipitation: record.precipitation,
                                     temperature: record.temperature),
                wasBad: record.feeling == HealthFeeling.bad.rawValue)
        }
    }

    func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<CheckInRecord>())
    }

    /// 記録のある暦日の数（累計。連続ではない）。着せ替えの解放と見返り表示に使う（設計書 §6.7）。
    func recordedDayCount(calendar: Calendar) throws -> Int {
        let dates = try context.fetch(FetchDescriptor<CheckInRecord>()).map(\.date)
        return Set(dates.map { calendar.startOfDay(for: $0) }).count
    }
}
