// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/WeatherKitAdapter.swift
// WeatherKit の毎時データを RiskEngine の WeatherPoint へ変換する。
// 単位の罠（0...1 の比率、Measurement の単位依存）を 1 箇所に閉じ込めてテストで守るため。
// 関連: ../RiskEngine/WeatherPoint.swift, docs/appcore-api.md, docs/riskengine-api.md §2.1
import Foundation
import RiskEngine
#if canImport(WeatherKit)
import WeatherKit
#endif

/// WeatherKit の `HourWeather` と同じ名前・型のプロパティ。
///
/// `HourWeather` は公開 init を持たずテストで組めないので、同じ形のプロトコルを切り、
/// 変換ロジックはスタブで検証する。`HourWeather` 自体は空の適合で通す。
public protocol HourlyWeatherSample {
    var date: Date { get }
    var pressure: Measurement<UnitPressure> { get }
    var temperature: Measurement<UnitTemperature> { get }
    /// 0...1 の比率。WeatherKit の仕様。
    var humidity: Double { get }
    /// 0...1 の比率。WeatherKit の仕様。
    var precipitationChance: Double { get }
    var precipitationAmount: Measurement<UnitLength> { get }
}

#if canImport(WeatherKit)
extension HourWeather: HourlyWeatherSample {}
#endif

extension WeatherPoint {
    /// 単位を hPa / ℃ / % / mm へ揃える。
    ///
    /// ここを経由せずに `.value` を渡すと、気圧が inHg（≒29.9）になって
    /// 気圧変化スコア（18pt 中 8pt）が恒久的に 0 になる。湿度と降水確率は
    /// 100 倍しないと 0...1 のまま閾値（75、60）に届かず、こちらも静かに 0 になる。
    public init(_ sample: some HourlyWeatherSample) {
        self.init(date: sample.date,
                  pressure: sample.pressure.converted(to: .hectopascals).value,
                  temperature: sample.temperature.converted(to: .celsius).value,
                  humidity: sample.humidity * 100,
                  precipitationChance: sample.precipitationChance * 100,
                  precipitationAmount: sample.precipitationAmount.converted(to: .millimeters).value)
    }
}

public enum WeatherSeries {
    /// 時刻昇順・同時刻の重複なしの系列に整える。
    ///
    /// `RiskAnalyzer` は昇順・1 時間刻みを前提に index で窓を取る（検証はしない）。
    /// 並び順と重複はここで保証する。等間隔は WeatherKit の hourly が毎時であることに
    /// 依存しており、検証していない。
    public static func hourly(from samples: [some HourlyWeatherSample]) -> [WeatherPoint] {
        var seen = Set<Date>()
        return samples
            .sorted { $0.date < $1.date }
            .compactMap { seen.insert($0.date).inserted ? WeatherPoint($0) : nil }
    }
}
