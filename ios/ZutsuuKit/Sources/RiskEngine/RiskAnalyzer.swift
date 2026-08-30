import Foundation

/// 1 時刻分のリスク判定結果。
/// 通常はエンジンが算出するが、SwiftUI プレビューやテストが合成のリスク曲線を
/// 組み立てられるよう init も公開している。
public struct HourlyRisk: Sendable, Equatable {
    public let point: WeatherPoint
    public let assessment: RiskAssessment
    public let pressureChanges: PressureChanges

    public init(point: WeatherPoint, assessment: RiskAssessment, pressureChanges: PressureChanges) {
        self.point = point
        self.assessment = assessment
        self.pressureChanges = pressureChanges
    }
}

/// 時系列全体にスコアリングを適用してリスク曲線を作る。
public struct RiskAnalyzer: Sendable {
    /// 前方窓の最大深さ（時間）。この時間ぶんの末尾は完全な窓が取れない。
    public static let lookaheadHours = 6

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

    /// 系列末尾 `lookaheadHours` 時間は前方窓が系列外に出るため返さない。
    /// 72 時間の予報を渡せば 66 時間ぶんのリスク曲線が返る。
    ///
    /// 末尾を「不完全な値で返す」のではなく切り詰めるのは、
    /// 窓が欠けた点のスコアが本物の平穏と見分けが付かないため。
    /// 8 時間かけて 24hPa 下がる系列でも、末尾が欠けていれば全域が
    /// `.slight` 以下に潰れ、`AlertScheduler` は 1 件も予約しない。
    /// 静かな誤検出（false calm）は製品の中核機能を失わせるうえ気付けない。
    /// 点数が減ることは呼び出し側から見えるが、劣化した値は正常に見える。
    /// 末尾の一部では 1h・3h の窓がまだ有効だが、その部分的な情報より
    /// 「評価できない点を返さない」ことを優先する。
    public func analyze(_ series: [WeatherPoint]) -> [HourlyRisk] {
        series.indices.dropLast(Self.lookaheadHours).map { index in
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
                temperatureChange3h: temperatureChange(series, at: index, hoursAhead: 3)
            )

            return HourlyRisk(point: point, assessment: assessment, pressureChanges: changes)
        }
    }
}
