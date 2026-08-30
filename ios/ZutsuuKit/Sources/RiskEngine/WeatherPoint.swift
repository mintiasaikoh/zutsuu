import Foundation

/// 気象データの中立表現。アプリ層が WeatherKit から変換して渡す。
/// RiskEngine が WeatherKit に依存しないための境界。
public struct WeatherPoint: Sendable, Equatable {
    public let date: Date
    public let pressure: Double            // hPa（海面気圧）
    public let temperature: Double         // ℃
    public let humidity: Double            // %（0〜100）
    public let precipitationChance: Double // %（0〜100）
    public let precipitationAmount: Double // mm

    public init(date: Date, pressure: Double, temperature: Double,
                humidity: Double, precipitationChance: Double, precipitationAmount: Double) {
        self.date = date
        self.pressure = pressure
        self.temperature = temperature
        self.humidity = humidity
        self.precipitationChance = precipitationChance
        self.precipitationAmount = precipitationAmount
    }
}
