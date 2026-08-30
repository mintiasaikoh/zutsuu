import Testing
@testable import RiskEngine

/// 移植元 `src/index.ts` の `computeCompositeRisk` と同じ入力で同じ内訳が出ることを固定する。
///
/// 期待値は TypeScript 実装を実際に走らせて採取したものであり、手計算ではない。
/// したがってここが赤くなった場合は期待値ではなく Swift 側の移植バグを疑うこと。
///
/// 絶対気圧の項だけは意図的に方式を変えている（固定閾値 → 地点別パーセンタイル）。
/// そのため TypeScript 側は 1013hPa（固定閾値 1005 より上＝0pt）で採取し、
/// Swift 側は `pressurePercentile: 0.5`（同じく 0pt）で比較する。
/// この項を両側で 0 に固定することで、残りの論理が一対一で対応する。
@Suite("TypeScript 実装との一致")
struct ParityTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let oneHour: Double
        let threeHour: Double
        let sixHour: Double
        let humidity: Double
        let precipitationChance: Double
        let precipitationAmount: Double
        let temperatureChange3h: Double

        let score: Int
        let level: RiskLevel
        /// TypeScript の `pressureScore`。採取時の 1013hPa では絶対気圧の項が 0 なので、
        /// Swift の `factors.pressureChange`（変化量のみ）と直接比較できる。
        let pressureChange: Int
        let humidityScore: Int
        let precipitation: Int
        let temperature: Int

        var testDescription: String {
            "1h=\(oneHour) 3h=\(threeHour) 6h=\(sixHour) "
            + "湿度=\(humidity) 降水確率=\(precipitationChance) 降水量=\(precipitationAmount) "
            + "気温変化=\(temperatureChange3h) → \(score)pt"
        }
    }

    /// 採取した 6 ケース。
    /// 4 件目は「上昇でも下降と同じく危険に達する」（絶対値評価）を固定する。
    /// 6 件目は気圧以外の全入力を閾値の直下に置き（湿度 74・降水確率 59・
    /// 気温 4.9・降水量はちょうど 2）、いずれも 0pt であることを固定する。
    static let cases: [Case] = [
        Case(oneHour: -4, threeHour: -8, sixHour: -10,
             humidity: 90, precipitationChance: 90, precipitationAmount: 5,
             temperatureChange3h: -8,
             score: 15, level: .danger,
             pressureChange: 8, humidityScore: 3, precipitation: 2, temperature: 2),
        Case(oneHour: -2, threeHour: -4, sixHour: -6,
             humidity: 75, precipitationChance: 60, precipitationAmount: 0,
             temperatureChange3h: -5,
             score: 7, level: .danger,
             pressureChange: 3, humidityScore: 2, precipitation: 1, temperature: 1),
        Case(oneHour: 0, threeHour: 0, sixHour: 0,
             humidity: 50, precipitationChance: 0, precipitationAmount: 0,
             temperatureChange3h: 0,
             score: 0, level: .calm,
             pressureChange: 0, humidityScore: 0, precipitation: 0, temperature: 0),
        Case(oneHour: 3, threeHour: 6, sixHour: 10,
             humidity: 60, precipitationChance: 30, precipitationAmount: 1,
             temperatureChange3h: 6,
             score: 7, level: .danger,
             pressureChange: 6, humidityScore: 0, precipitation: 0, temperature: 1),
        Case(oneHour: -5, threeHour: -9, sixHour: -12,
             humidity: 85, precipitationChance: 80, precipitationAmount: 3,
             temperatureChange3h: -9,
             score: 15, level: .danger,
             pressureChange: 8, humidityScore: 3, precipitation: 2, temperature: 2),
        Case(oneHour: 2, threeHour: 4, sixHour: 6,
             humidity: 74, precipitationChance: 59, precipitationAmount: 2,
             temperatureChange3h: 4.9,
             score: 3, level: .slight,
             pressureChange: 3, humidityScore: 0, precipitation: 0, temperature: 0),
    ]

    /// 合計だけを見ると、2 つの要因が逆向きに同じだけ誤っていても打ち消し合って通る。
    /// そのため内訳を要因ごとに個別に表明する。
    @Test("採取した入力で内訳まで一致する", arguments: cases)
    func matchesTypeScript(testCase: Case) {
        let result = compositeRisk(
            pressureChanges: PressureChanges(oneHour: testCase.oneHour,
                                             threeHour: testCase.threeHour,
                                             sixHour: testCase.sixHour),
            pressurePercentile: 0.5,
            humidity: testCase.humidity,
            precipitationChance: testCase.precipitationChance,
            precipitationAmount: testCase.precipitationAmount,
            temperatureChange3h: testCase.temperatureChange3h
        )

        #expect(result.factors.pressureChange == testCase.pressureChange)
        #expect(result.factors.humidity == testCase.humidityScore)
        #expect(result.factors.precipitation == testCase.precipitation)
        #expect(result.factors.temperature == testCase.temperature)
        // 採取時の 1013hPa に対応する 0pt。ここが 0 でないと合計の比較が成り立たない。
        #expect(result.factors.pressureBaseline == 0)
        #expect(result.score == testCase.score)
        #expect(result.level == testCase.level)
    }
}
