import Foundation

/// 1 時刻分のリスク判定結果。
/// memberwise init は internal のまま（エンジン内部でのみ生成する）。
public struct HourlyRisk: Sendable, Equatable {
    public let point: WeatherPoint
    public let assessment: RiskAssessment
    public let pressureChanges: PressureChanges
}

/// 時系列全体にスコアリングを適用してリスク曲線を作る。
public struct RiskAnalyzer: Sendable {
    private let climatology: any PressureClimatology
    private let latitude: Double
    private let longitude: Double
    private let calendar: Calendar

    public init(climatology: any PressureClimatology,
                latitude: Double, longitude: Double,
                calendar: Calendar = .current) {
        self.climatology = climatology
        self.latitude = latitude
        self.longitude = longitude
        self.calendar = calendar
    }

    public func analyze(_ series: [WeatherPoint]) -> [HourlyRisk] {
        series.indices.map { index in
            let point = series[index]
            let changes = pressureChanges(series, at: index)
            let month = calendar.component(.month, from: point.date)

            let assessment = compositeRisk(
                pressureChanges: changes,
                pressurePercentile: climatology.percentile(
                    pressure: point.pressure,
                    latitude: latitude, longitude: longitude, month: month),
                humidity: point.humidity,
                precipitationChance: point.precipitationChance,
                precipitationAmount: point.precipitationAmount,
                temperatureChange3h: temperatureChange(series, at: index, hoursAgo: 3)
            )

            return HourlyRisk(point: point, assessment: assessment, pressureChanges: changes)
        }
    }
}
