/// 前日比の最高気温差による寒暖差注意報。
/// 移植元は src/index.ts の `detectTemperatureSwing()`。
///
/// 移植元の `diff` は絶対値だったが、ここでは符号を残す。
/// 「暖かくなる」「冷え込む」でアドバイス文面が変わるため、
/// 判定側だけが絶対値を取る形にしている。
public struct TemperatureSwing: Sendable, Equatable {
    /// 注意報を出す前日比（℃）。
    public static let threshold: Double = 5

    public let todayMax: Double
    public let yesterdayMax: Double

    public init(todayMax: Double, yesterdayMax: Double) {
        self.todayMax = todayMax
        self.yesterdayMax = yesterdayMax
    }

    /// 前日比の差。正なら暖かくなる、負なら冷え込む。
    public var difference: Double { todayMax - yesterdayMax }

    /// 上昇・下降のどちらでも自律神経に負荷がかかるため絶対値で判定する。
    public var hasAlert: Bool { abs(difference) >= Self.threshold }
}
