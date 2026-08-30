import Foundation

/// 気象データの中立表現。アプリ層が WeatherKit から変換して渡す。
/// RiskEngine が WeatherKit に依存しないための境界。
public struct WeatherPoint: Sendable, Hashable {
    public let date: Date

    /// 海面気圧（hPa）
    public let pressure: Double

    /// 気温（℃）
    public let temperature: Double

    /// 相対湿度（%、0〜100）。
    /// - Warning: WeatherKit の `humidity` は 0...1 の割合で提供されるため、
    ///   アダプタ側で 100 倍してから渡すこと。
    public let humidity: Double

    /// 降水確率（%、0〜100）。
    /// - Warning: WeatherKit の `precipitationChance` は 0...1 の割合で提供されるため、
    ///   アダプタ側で 100 倍してから渡すこと。
    public let precipitationChance: Double

    /// 降水量（mm）
    public let precipitationAmount: Double

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
