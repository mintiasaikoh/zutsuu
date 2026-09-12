// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/WeatherProvider.swift
// WeatherKit の呼び出しを 1 箇所に閉じ込め、HourlyWeatherSample として返す。
// 単位変換を AppCore のアダプタ以外で行わせないため（appcore-api.md §3.1）。
// 関連: ../../ZutsuuKit/Sources/AppCore/WeatherKitAdapter.swift, ForecastPipeline.swift
import CoreLocation
import Foundation
import WeatherKit
import AppCore
import RiskEngine

/// Apple Weather の帰属表示に必要な情報（設計書 §9）。
struct WeatherAttribution: Sendable {
    let legalPageURL: URL
    let markURL: URL
}

/// 予報の取得口。時刻昇順・重複なし・有限値の `WeatherPoint` 列を返す。テストでは差し替える。
protocol WeatherProviding: Sendable {
    func hourly(at coordinate: Coordinate, from start: Date, to end: Date) async throws -> [WeatherPoint]
    func attribution() async throws -> WeatherAttribution
}

struct WeatherKitProvider: WeatherProviding {
    /// `WeatherPoint` は必ず `HourlyWeatherSample` 経由で作る（appcore-api.md §3.1）。換算はここだけ。
    func hourly(at coordinate: Coordinate, from start: Date, to end: Date) async throws -> [WeatherPoint] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let forecast = try await WeatherService.shared.weather(
            for: location, including: .hourly(startDate: start, endDate: end))
        return WeatherSeries.hourly(from: forecast.forecast)
    }

    func attribution() async throws -> WeatherAttribution {
        let attribution = try await WeatherService.shared.attribution
        return WeatherAttribution(legalPageURL: attribution.legalPageURL,
                                  markURL: attribution.combinedMarkLightURL)
    }
}
