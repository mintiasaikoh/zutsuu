import Foundation

/// 1 時刻分のリスク判定結果。
/// 通常はエンジンが算出するが、SwiftUI プレビューやテストが合成のリスク曲線を
/// 組み立てられるよう init も公開している。
public struct HourlyRisk: Sendable, Equatable, Identifiable {
    public let point: WeatherPoint
    public let assessment: RiskAssessment
    public let pressureChanges: PressureChanges

    /// SwiftUI の `List` / `ForEach` 用の識別子（Plan 3）。
    /// 1 本のリスク曲線の中で時刻は一意（`RiskAnalyzer.analyze` は 1 時間刻みの
    /// 系列をそのまま写す）なので、時刻がそのまま識別子になる。
    public var id: Date { point.date }

    public init(point: WeatherPoint, assessment: RiskAssessment, pressureChanges: PressureChanges) {
        self.point = point
        self.assessment = assessment
        self.pressureChanges = pressureChanges
    }
}

/// 時系列全体にスコアリングを適用してリスク曲線を作る。
///
/// - Important: 解析のたびに新しく生成すること。長寿命の依存として保持してはいけない。
///   `Calendar` は値型なので、生成した時点のタイムゾーンを写し取って固定する。
///   本アプリは移動するユーザーを想定した全世界向けであり、設計書 §5.2 は
///   端末ローカル時刻での判定を要求している。生成したまま持ち回ると、
///   ユーザーがタイムゾーンをまたいだ後も古いタイムゾーンで月を読み続け、
///   月境界の前後で平年分布の参照月がずれる。
///   同じ理由が `AlertScheduler`（静穏時間の壁時計判定）にも当てはまる。
public struct RiskAnalyzer: Sendable {
    /// 前方窓の最大深さ（時間）。この時間ぶんの末尾は完全な窓が取れない。
    public static let lookaheadHours = 6

    private let climatology: any PressureClimatology
    private let coordinate: Coordinate
    private let calendar: Calendar
    private let gregorian: Calendar

    public init(climatology: any PressureClimatology,
                coordinate: Coordinate,
                calendar: Calendar = .current) {
        self.climatology = climatology
        self.coordinate = coordinate
        self.calendar = calendar
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.gregorian = gregorian
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
            // 平年値テーブルは西暦の季節月で作られている。端末の暦（イスラム暦等）の月番号を
            // 渡すと季節の違う分布で採点するため、タイムゾーンだけ引き継いでグレゴリオ暦で数える（レビュー R21）。
            let month = gregorian.component(.month, from: point.date)

            let assessment = compositeRisk(
                pressureChanges: changes,
                pressurePercentile: climatology.percentile(
                    pressure: point.pressure, coordinate: coordinate, month: month),
                humidity: point.humidity,
                precipitationChance: point.precipitationChance,
                precipitationAmount: point.precipitationAmount,
                temperatureChange3h: temperatureChange(series, at: index, hoursAhead: 3)
            )

            return HourlyRisk(point: point, assessment: assessment, pressureChanges: changes)
        }
    }
}
