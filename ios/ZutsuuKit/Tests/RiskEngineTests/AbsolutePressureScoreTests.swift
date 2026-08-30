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
        let p = climatology.percentile(pressure: 1008, latitude: 1.35, longitude: 103.8, month: 7)
        #expect(absolutePressureScore(percentile: p) == 0)
    }

    /// 固定閾値では 1030hPa 常態の地域が永久に発火しなかった。
    @Test("高緯度内陸でも相対的に低ければ発火する")
    func highLatitudeRelativeLowFires() {
        let climatology = StubClimatology(value: 0.05)
        let p = climatology.percentile(pressure: 1015, latitude: 47.9, longitude: 106.9, month: 1)
        #expect(absolutePressureScore(percentile: p) == 3)
    }

    @Test("範囲外のパーセンタイルは 0.0〜1.0 に丸められる")
    func outOfRangeIsClamped() {
        #expect(absolutePressureScore(percentile: -0.5) == 3)
        #expect(absolutePressureScore(percentile: 1.5) == 0)
    }

    /// 非有限値は Plan 6 の実装バグ。デバッグでは `assertionFailure` で停止し、
    /// リリースでは 0 を返して通知が静かに止まらないようにする。
    @Test("非有限値はデバッグビルドで検出される")
    func nonFiniteIsCaughtInDebug() async {
        await #expect(processExitsWith: .failure) {
            _ = absolutePressureScore(percentile: .nan)
        }
    }
}
