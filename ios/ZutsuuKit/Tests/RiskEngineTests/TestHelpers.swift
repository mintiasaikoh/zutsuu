import Foundation
import RiskEngine

/// `PressureClimatology` は public API（アプリ層が実装を注入する唯一の口）。
/// ここを素の `import` にしておくことで、`public` の付け忘れをビルドが検出する。
struct StubClimatology: PressureClimatology {
    let value: Double
    func percentile(pressure: Double, latitude: Double, longitude: Double, month: Int) -> Double {
        value
    }
}

func makeSeries(pressures: [Double], temperatures: [Double]? = nil) -> [WeatherPoint] {
    let base = Date(timeIntervalSince1970: 0)
    return pressures.enumerated().map { index, pressure in
        WeatherPoint(date: base.addingTimeInterval(TimeInterval(index) * 3600),
                     pressure: pressure,
                     temperature: temperatures?[index] ?? 20,
                     humidity: 50, precipitationChance: 0, precipitationAmount: 0)
    }
}
