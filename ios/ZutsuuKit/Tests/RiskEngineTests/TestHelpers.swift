import Foundation
import RiskEngine

/// `PressureClimatology` は public API（アプリ層が実装を注入する唯一の口）。
/// ここを素の `import` にしておくことで、`public` の付け忘れをビルドが検出する。
struct StubClimatology: PressureClimatology {
    let value: Double
    func percentile(pressure: Double, coordinate: Coordinate, month: Int) -> Double {
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
/// `RiskAnalyzer` が座標・月・気圧をそのまま渡しているかを外側から固定するために使う。
/// クロージャを保持するだけなので可変状態を持たず、`Sendable` 要件と衝突しない。
struct ClosureClimatology: PressureClimatology {
    let body: @Sendable (_ pressure: Double, _ coordinate: Coordinate, _ month: Int) -> Double
    func percentile(pressure: Double, coordinate: Coordinate, month: Int) -> Double {
        body(pressure, coordinate, month)
    }
}

/// テストで使う代表地点（練馬区）。
let tokyo = Coordinate(latitude: 35.7, longitude: 139.6)

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func utcDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day,
                                          hour: hour, minute: minute))!
}

/// `AlertScheduler` のテスト用に、レベルの並びからリスク曲線を直接組み立てる。
///
/// スケジューラが見るのは「どの時刻にレベルが上がるか」だけなので、
/// 気象データからスコアを算出させるより並びを直接書くほうが意図が読める。
/// 日付は UTC 固定。壁時計時刻に依存する静穏時間の判定を、
/// 実行環境のタイムゾーンから切り離すため。
func makeRiskCurve(levels: [RiskLevel],
                   startHour: Int = 12,
                   day: Date = utcDate(year: 2026, month: 3, day: 10)) -> [HourlyRisk] {
    let base = day.addingTimeInterval(TimeInterval(startHour) * 3600)
    return levels.enumerated().map { index, level in
        HourlyRisk(
            point: WeatherPoint(date: base.addingTimeInterval(TimeInterval(index) * 3600),
                                pressure: 1013, temperature: 20, humidity: 50,
                                precipitationChance: 0, precipitationAmount: 0),
            assessment: curveAssessment(level),
            pressureChanges: PressureChanges(oneHour: 0, threeHour: 0, sixHour: 0))
    }
}

/// `makeRiskCurve` が各レベルに与える判定。
/// レベルごとにスコアが違うので、`ScheduledAlert` がどの時点の判定を
/// 抱えているかを外側から見分けられる。
func curveAssessment(_ level: RiskLevel) -> RiskAssessment {
    // CompositeRisk.swift の閾値に対応する代表的なスコア。
    let score = switch level {
    case RiskLevel.calm: 0
    case .slight: 1
    case .caution: 4
    case .danger: 7
    }
    return RiskAssessment(level: level, score: score,
                          factors: RiskFactors(pressureChange: score, pressureBaseline: 0,
                                               humidity: 0, precipitation: 0, temperature: 0))
}
