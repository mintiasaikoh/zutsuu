// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/AppCoreTests/TestSupport.swift
// AppCore テスト共通の日時・系列フィクスチャ。
// RiskEngineTests のヘルパはターゲット外で共有できないため、必要最小限を持つ。
// 関連: ../RiskEngineTests/TestHelpers.swift
import Foundation
import RiskEngine

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

let tokyoCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

func utc(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 3, day: day,
                                          hour: hour, minute: minute))!
}

func point(_ date: Date, temperature: Double = 20, pressure: Double = 1013,
           humidity: Double = 50, chance: Double = 10, amount: Double = 0) -> WeatherPoint {
    WeatherPoint(date: date, pressure: pressure, temperature: temperature,
                 humidity: humidity, precipitationChance: chance, precipitationAmount: amount)
}

func assessment(_ level: RiskLevel, score: Int, factors: RiskFactors) -> RiskAssessment {
    RiskAssessment(level: level, score: score, factors: factors)
}

func alert(kind: AlertKind, fire: Date, target: Date,
           level: RiskLevel = .caution, score: Int = 5,
           factors: RiskFactors = RiskFactors(pressureChange: 4, pressureBaseline: 0,
                                              humidity: 1, precipitation: 0,
                                              temperature: 0)) -> ScheduledAlert {
    ScheduledAlert(fireDate: fire, targetDate: target,
                   assessment: assessment(level, score: score, factors: factors), kind: kind)
}
