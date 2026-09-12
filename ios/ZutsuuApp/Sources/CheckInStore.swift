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
    /// 記録時点の気象の生値とレベル。ログ表示用（学習には点数のほうを使う）。
    /// 後から足した optional なので、古い記録では nil。
    var levelRaw: Int?
    var pressureHPa: Double?
    var pressureChange3h: Double?
    var humidityPercent: Double?
    var precipitationChance: Double?
    var temperatureC: Double?

    init(checkIn: HealthCheckIn, risk: HourlyRisk?) {
        id = checkIn.id
        date = checkIn.date
        feeling = checkIn.feeling.rawValue
        let factors = risk?.assessment.factors
        hasFactors = factors != nil
        pressureChange = factors?.pressureChange ?? 0
        pressureBaseline = factors?.pressureBaseline ?? 0
        humidity = factors?.humidity ?? 0
        precipitation = factors?.precipitation ?? 0
        temperature = factors?.temperature ?? 0
        levelRaw = risk?.assessment.level.rawValue
        pressureHPa = risk?.point.pressure
        pressureChange3h = risk?.pressureChanges.threeHour
        humidityPercent = risk?.point.humidity
        precipitationChance = risk?.point.precipitationChance
        temperatureC = risk?.point.temperature
    }

    var factors: RiskFactors {
        RiskFactors(pressureChange: pressureChange, pressureBaseline: pressureBaseline,
                    humidity: humidity, precipitation: precipitation, temperature: temperature)
    }

    /// 後から取れた予報の要因と生値を書き込む（`backfillFactors`）。
    func apply(_ risk: HourlyRisk) {
        let factors = risk.assessment.factors
        hasFactors = true
        pressureChange = factors.pressureChange
        pressureBaseline = factors.pressureBaseline
        humidity = factors.humidity
        precipitation = factors.precipitation
        temperature = factors.temperature
        levelRaw = risk.assessment.level.rawValue
        pressureHPa = risk.point.pressure
        pressureChange3h = risk.pressureChanges.threeHour
        humidityPercent = risk.point.humidity
        precipitationChance = risk.point.precipitationChance
        temperatureC = risk.point.temperature
    }
}

@MainActor
final class CheckInStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 同じ ID が既にあれば何もしない（保存結果が不明な再試行への備え）。
    func save(_ checkIn: HealthCheckIn, risk: HourlyRisk?) throws {
        let id = checkIn.id
        var descriptor = FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if try context.fetchCount(descriptor) > 0 { return }
        context.insert(CheckInRecord(checkIn: checkIn, risk: risk))
        do {
            try context.save()
        } catch {
            // 保存に失敗した insert を context に残すと、次の fetch が「保存済み」と誤認して
            // 再試行を早期 return させる（レビュー: 保存失敗後の再試行）。巻き戻す。
            context.rollback()
            throw error
        }
    }

    /// 要因なしで保存した記録に、後から取れた予報の要因を付ける（レビュー R09）。
    /// 系列に入口時刻がある記録だけを更新し、更新した件数を返す。スキーマは変えない。
    @discardableResult
    func backfillFactors(risk: (Date) -> HourlyRisk?) throws -> Int {
        let descriptor = FetchDescriptor<CheckInRecord>(predicate: #Predicate { !$0.hasFactors })
        var updated = 0
        for record in try context.fetch(descriptor) {
            guard let hourly = risk(record.date) else { continue }
            record.apply(hourly)
            updated += 1
        }
        if updated > 0 { try context.save() }
        return updated
    }

    /// 要因付きの記録だけを学習に使う。
    func observations() throws -> [SymptomObservation] {
        let descriptor = FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.hasFactors })
        return try context.fetch(descriptor).map { record in
            SymptomObservation(factors: record.factors,
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
