// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/AppCoreTests/WeatherKitAdapterTests.swift
// WeatherKit 相当のサンプルから WeatherPoint への単位変換を検証する。
// 仕様書 §2.1 の「単位の罠」をアダプタ側のテストで防御するため。
// 関連: ../../Sources/AppCore/WeatherKitAdapter.swift, docs/riskengine-api.md §2.1
import Testing
import Foundation
import AppCore
import RiskEngine

/// WeatherKit の `HourWeather` と同じ形のスタブ。単位を意図的に非 SI で持たせる。
private struct Sample: HourlyWeatherSample {
    var date: Date
    var pressure: Measurement<UnitPressure>
    var temperature: Measurement<UnitTemperature>
    var humidity: Double
    var precipitationChance: Double
    var precipitationAmount: Measurement<UnitLength>
}

private func sample(_ date: Date,
                    pressure: Measurement<UnitPressure> = .init(value: 1013, unit: .hectopascals),
                    temperature: Measurement<UnitTemperature> = .init(value: 20, unit: .celsius),
                    humidity: Double = 0.5, chance: Double = 0.1,
                    amount: Measurement<UnitLength> = .init(value: 0, unit: .millimeters)) -> Sample {
    Sample(date: date, pressure: pressure, temperature: temperature,
           humidity: humidity, precipitationChance: chance, precipitationAmount: amount)
}

@Suite("WeatherKit アダプタ")
struct WeatherKitAdapterTests {

    /// 0...1 の比率をそのまま渡すと湿度・降水のスコアが恒久的に 0 になる。
    /// 100 倍されて % になっていることを固定する。
    @Test("湿度と降水確率は比率から%へ変換される")
    func ratiosBecomePercent() {
        let converted = WeatherPoint(sample(utc(10), humidity: 0.85, chance: 0.6))
        #expect(converted.humidity == 85)
        #expect(converted.precipitationChance == 60)
    }

    /// inHg のまま `.value` を取ると気圧が 29.9 になり、気圧変化スコア（8pt）が消える。
    @Test("気圧はどの単位で来ても hPa に揃う")
    func pressureConvertsToHectopascals() {
        let inHg = Measurement<UnitPressure>(value: 29.92, unit: .inchesOfMercury)
        let converted = WeatherPoint(sample(utc(10), pressure: inHg))
        #expect(abs(converted.pressure - 1013.2) < 0.5)
    }

    @Test("気温は ℃、降水量は mm に揃う")
    func temperatureAndAmountConvert() {
        let converted = WeatherPoint(sample(
            utc(10),
            temperature: .init(value: 86, unit: .fahrenheit),
            amount: .init(value: 0.1, unit: .inches)))
        #expect(abs(converted.temperature - 30) < 0.01)
        #expect(abs(converted.precipitationAmount - 2.54) < 0.01)
    }

    @Test("日時はそのまま保持される")
    func datePreserved() {
        #expect(WeatherPoint(sample(utc(10, 15))).date == utc(10, 15))
    }

    /// `RiskAnalyzer` は昇順・重複なしを検証せず index で窓を取る。
    /// 並び順と重複はアダプタが保証する。
    @Test("系列は時刻昇順に並び、同時刻の重複は最初の1件だけ残る")
    func seriesSortedAndDeduplicated() {
        let series = WeatherSeries.hourly(from: [
            sample(utc(10, 2), humidity: 0.2),
            sample(utc(10, 0)),
            sample(utc(10, 1)),
            sample(utc(10, 2), humidity: 0.9),
        ])
        #expect(series.map(\.date) == [utc(10, 0), utc(10, 1), utc(10, 2)])
        #expect(series[2].humidity == 20)
    }

    @Test("空の入力は空の系列になる")
    func emptySeries() {
        #expect(WeatherSeries.hourly(from: [Sample]()).isEmpty)
    }
}
