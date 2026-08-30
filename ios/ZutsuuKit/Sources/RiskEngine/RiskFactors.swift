public struct RiskFactors: Sendable, Equatable {
    public let pressure: Int
    public let humidity: Int
    public let precipitation: Int
    public let temperature: Int

    public init(pressure: Int, humidity: Int, precipitation: Int, temperature: Int) {
        self.pressure = pressure
        self.humidity = humidity
        self.precipitation = precipitation
        self.temperature = temperature
    }

    public var total: Int { pressure + humidity + precipitation + temperature }
}
