/// 各時間窓での気圧変化量（hPa）。負値が気圧低下を表す。
public struct PressureChanges: Sendable, Equatable {
    /// 1 時間前との差（hPa）
    public let oneHour: Double
    /// 3 時間前との差（hPa）
    public let threeHour: Double
    /// 6 時間前との差（hPa）
    public let sixHour: Double

    public init(oneHour: Double, threeHour: Double, sixHour: Double) {
        self.oneHour = oneHour
        self.threeHour = threeHour
        self.sixHour = sixHour
    }
}
