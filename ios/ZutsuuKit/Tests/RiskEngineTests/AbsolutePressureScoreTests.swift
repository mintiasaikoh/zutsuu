import Testing
@testable import RiskEngine

@Suite("絶対気圧スコア")
struct AbsolutePressureScoreTests {

    @Test("パーセンタイルからスコアへの変換", arguments: [
        (0.05, 3), (0.099, 3), (0.10, 2), (0.24, 2), (0.25, 1), (0.39, 1), (0.40, 0), (0.90, 0)
    ])
    func conversion(percentile: Double, expected: Int) {
        #expect(absolutePressureScore(percentile: percentile) == expected)
    }

    /// 設計書 §5.1 の破綻ケース。固定閾値では熱帯が常時アラートになっていた。
    @Test("熱帯の平常時の気圧はアラートにならない")
    func tropicalNormalIsCalm() {
        let climatology = StubClimatology(value: 0.50)
        let p = climatology.percentile(pressure: 1008,
                                       coordinate: Coordinate(latitude: 1.35, longitude: 103.8),
                                       month: 7)
        #expect(absolutePressureScore(percentile: p) == 0)
    }

    /// 固定閾値では 1030hPa 常態の地域が永久に発火しなかった。
    @Test("高緯度内陸でも相対的に低ければ発火する")
    func highLatitudeRelativeLowFires() {
        let climatology = StubClimatology(value: 0.05)
        let p = climatology.percentile(pressure: 1015,
                                       coordinate: Coordinate(latitude: 47.9, longitude: 106.9),
                                       month: 1)
        #expect(absolutePressureScore(percentile: p) == 3)
    }

    /// clamp が有るか無いかでは結果が変わらない（閾値が全て片側 `<` のため）。
    /// このテストが固定しているのは clamp の実装ではなく、
    /// 「範囲外入力でも定義済みのスコアを返す」という関数の全域性。
    @Test("範囲外のパーセンタイルでも定義されたスコアを返す")
    func outOfRangeStillReturnsDefinedScore() {
        #expect(absolutePressureScore(percentile: -0.5) == 3)
        #expect(absolutePressureScore(percentile: 1.5) == 0)
    }

    // 非有限値は Plan 6 の実装バグ。デバッグでは `assertionFailure` で停止させ、
    // リリースではコンパイルされて消えるため 0 を返す。契約が構成ごとに異なるので
    // テストも分ける（SwiftPM が debug ビルドで DEBUG を定義する）。
    #if DEBUG
    @Test("非有限値はデバッグビルドで検出される")
    func nonFiniteIsCaughtInDebug() async {
        await #expect(processExitsWith: .failure) {
            _ = absolutePressureScore(percentile: .nan)
        }
    }
    #else
    @Test("非有限値はリリースビルドで 0 を返す")
    func nonFiniteReturnsZeroInRelease() {
        #expect(absolutePressureScore(percentile: .nan) == 0)
        #expect(absolutePressureScore(percentile: .infinity) == 0)
    }
    #endif
}
