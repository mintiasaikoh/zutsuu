// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/RiskFactors.swift
// 要因ごとの点数（気圧変化・絶対気圧・湿度・降水・気温変動）。
// 合計だけでなく内訳を持ち、通知文面と個人化の説明変数に使うため。
// 関連: CompositeRisk.swift, ../PersonalRisk/PersonalRiskModel.swift
/// 複合リスクスコアの内訳。
public struct RiskFactors: Sendable, Hashable {
    /// 気圧の変化量スコア（0〜8）。「急降下中」を表す。
    public let pressureChange: Int
    /// その土地としての気圧の低さスコア（0〜3）。「この土地としては低い気圧」を表す。
    public let pressureBaseline: Int
    public let humidity: Int
    public let precipitation: Int
    public let temperature: Int

    public init(pressureChange: Int, pressureBaseline: Int,
                humidity: Int, precipitation: Int, temperature: Int) {
        self.pressureChange = pressureChange
        self.pressureBaseline = pressureBaseline
        self.humidity = humidity
        self.precipitation = precipitation
        self.temperature = temperature
    }

    /// 気圧要因の合計（変化量＋その土地としての低さ）。
    public var pressure: Int { pressureChange + pressureBaseline }

    public var total: Int { pressure + humidity + precipitation + temperature }
}
