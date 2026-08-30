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

func makeSeries(pressures: [Double], temperatures: [Double]? = nil,
                humidity: Double = 50,
                precipitationChance: Double = 0,
                precipitationAmount: Double = 0,
                start base: Date = Date(timeIntervalSince1970: 0)) -> [WeatherPoint] {
    if let temperatures {
        precondition(temperatures.count == pressures.count,
                     """
                     temperatures は pressures と同じ要素数にすること                      (pressures: \(pressures.count), temperatures: \(temperatures.count))
                     """)
    }
    return pressures.enumerated().map { index, pressure in
        WeatherPoint(date: base.addingTimeInterval(TimeInterval(index) * 3600),
                     pressure: pressure,
                     temperature: temperatures?[index] ?? 20,
                     humidity: humidity,
                     precipitationChance: precipitationChance,
                     precipitationAmount: precipitationAmount)
    }
}

/// 引数を観測できる `PressureClimatology`。
/// `RiskAnalyzer` が緯度・経度・月・気圧をそのまま渡しているかを外側から固定するために使う。
/// クロージャを保持するだけなので可変状態を持たず、`Sendable` 要件と衝突しない。
struct ClosureClimatology: PressureClimatology {
    let body: @Sendable (_ pressure: Double, _ latitude: Double,
                         _ longitude: Double, _ month: Int) -> Double
    func percentile(pressure: Double, latitude: Double, longitude: Double, month: Int) -> Double {
        body(pressure, latitude, longitude, month)
    }
}

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func utcDate(year: Int, month: Int, day: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}
