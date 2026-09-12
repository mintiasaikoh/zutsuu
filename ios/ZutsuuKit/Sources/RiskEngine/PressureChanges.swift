// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/PressureChanges.swift
// ある時刻の 1h / 3h / 6h の気圧変化量をまとめた値型。
// 通知文面と点数化が同じ変化量を参照するため。
// 関連: PressureChange.swift, RiskAnalyzer.swift
/// 各時間窓での気圧変化量（hPa）。
///
/// 差は「その時刻から先」に向かって取る（前方差分）。
/// したがって負値は「これから下がる」を意味し、「すでに下がった」ではない。
/// この向きにより、値が大きくなるのは気圧低下の始まりの時刻であり、
/// 通知を低下が始まる前に出せる。詳細は `PressureChange.swift` を参照。
public struct PressureChanges: Sendable, Hashable {
    /// 1 時間後との差（hPa）
    public let oneHour: Double
    /// 3 時間後との差（hPa）
    public let threeHour: Double
    /// 6 時間後との差（hPa）
    public let sixHour: Double

    public init(oneHour: Double, threeHour: Double, sixHour: Double) {
        self.oneHour = oneHour
        self.threeHour = threeHour
        self.sixHour = sixHour
    }
}
