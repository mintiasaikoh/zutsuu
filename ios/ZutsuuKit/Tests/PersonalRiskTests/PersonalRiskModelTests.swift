// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/PersonalRiskTests/PersonalRiskModelTests.swift
// 個人化回帰の学習と通知判定を、汎用一致・縮小・符号制約を軸に検証する。
// 「記録ゼロなら較正済み事前分布に一致し、表示から 1 段以上ずれない」という §6.5 の約束を固定するため。
// 関連: ../../Sources/PersonalRisk/PersonalRiskModel.swift, docs/personalrisk-api.md
import Testing
import Foundation
import PersonalRisk
import RiskEngine

/// §3.6 のレベル変換をテスト側で独立に再現する。エンジンの実装を経由しないのは、
/// 「汎用モデルは仕様書の表と一致する」を実装同士の循環なしに表明するため。
private func specLevel(total: Int) -> RiskLevel {
    if total >= 7 { return .danger }
    if total >= 4 { return .caution }
    if total >= 1 { return .slight }
    return .calm
}

private func factors(_ pressureChange: Int = 0, baseline: Int = 0, humidity: Int = 0,
                     precipitation: Int = 0, temperature: Int = 0) -> RiskFactors {
    RiskFactors(pressureChange: pressureChange, pressureBaseline: baseline,
                humidity: humidity, precipitation: precipitation, temperature: temperature)
}

@Suite("個人化回帰モデル")
struct PersonalRiskModelTests {

    // MARK: - 汎用モデルとの一致

    /// 全 1296 通りの要因組み合わせで、`.generic` の通知判定が §3.6 の
    /// レベル変換と完全一致する。境界（合計 1・4・7pt ちょうど）の等号も含む。
    @Test("汎用モデルの通知判定は全組み合わせで仕様のレベル変換と一致する")
    func genericMatchesSpecLevels() {
        var checked = 0
        for pressureChange in 0...8 {
            for baseline in 0...3 {
                for humidity in 0...3 {
                    for precipitation in 0...2 {
                        for temperature in 0...2 {
                            let f = factors(pressureChange, baseline: baseline,
                                            humidity: humidity, precipitation: precipitation,
                                            temperature: temperature)
                            #expect(PersonalRiskModel.generic.schedulingLevel(for: f)
                                    == specLevel(total: f.total), "\(f)")
                            checked += 1
                        }
                    }
                }
            }
        }
        #expect(checked == 1296)
    }

    // MARK: - 較正済み事前分布（§3 1a）

    /// 較正は満点の logit を汎用と揃える正規化なので、0pt と 18pt の確率は汎用と一致する。
    @Test("較正済み事前分布は0ptと18ptで汎用と同じ確率になる")
    func calibratedMatchesGenericAtExtremes() {
        let calm = factors()
        let full = factors(8, baseline: 3, humidity: 3, precipitation: 2, temperature: 2)
        let calibrated = PersonalRiskModel.calibrated
        #expect(abs(calibrated.probability(of: calm) - PersonalRiskModel.generic.probability(of: calm)) < 1e-12)
        #expect(abs(calibrated.probability(of: full) - PersonalRiskModel.generic.probability(of: full)) < 1e-12)
        #expect(calibrated.intercept == PersonalRiskModel.generic.intercept)
    }

    /// 文献（Katsuki 2023、Dixon 2019）の順序: 湿度 > 気圧変化 > 絶対気圧 > 降水 = 気温変動。
    @Test("較正済みの重みは文献の順序を保つ")
    func calibratedKeepsLiteratureOrdering() {
        let m = PersonalRiskModel.calibrated
        #expect(m.humidity > m.pressureChange)
        #expect(m.pressureChange > m.pressureBaseline)
        #expect(m.pressureBaseline > m.precipitation)
        #expect(m.precipitation == m.temperature)
        for weight in [m.pressureChange, m.pressureBaseline, m.humidity, m.precipitation, m.temperature] {
            #expect(PersonalRiskModel.weightRange.contains(weight))
        }
    }

    /// 記録ゼロの通知判定が表示レベルからずれるのは 1 段まで。全 1296 通りで固定する。
    @Test("較正済み事前分布の通知判定は全組み合わせで表示レベルから1段以内")
    func calibratedStaysWithinOneLevelOfSpec() {
        var checked = 0
        var shifted = 0
        for pressureChange in 0...8 {
            for baseline in 0...3 {
                for humidity in 0...3 {
                    for precipitation in 0...2 {
                        for temperature in 0...2 {
                            let f = factors(pressureChange, baseline: baseline,
                                            humidity: humidity, precipitation: precipitation,
                                            temperature: temperature)
                            let level = PersonalRiskModel.calibrated.schedulingLevel(for: f)
                            let gap = abs(level.rawValue - specLevel(total: f.total).rawValue)
                            #expect(gap <= 1, "\(f)")
                            if gap == 1 { shifted += 1 }
                            checked += 1
                        }
                    }
                }
            }
        }
        #expect(checked == 1296)
        #expect(shifted > 0)
    }

    @Test("記録ゼロの学習は事前分布をそのまま返す")
    func emptyObservationsReturnPrior() {
        #expect(PersonalRiskModel.fitted(to: []) == .calibrated)
        #expect(PersonalRiskModel.fitted(to: [], prior: .generic) == .generic)
    }

    @Test("事前分布の強さが不正なら事前分布に倒す")
    func invalidPriorWeightFallsBackToPrior() {
        let observations = [SymptomObservation(factors: factors(humidity: 3), wasBad: true)]
        #expect(PersonalRiskModel.fitted(to: observations, priorWeight: 0) == .calibrated)
        #expect(PersonalRiskModel.fitted(to: observations, priorWeight: -1) == .calibrated)
        #expect(PersonalRiskModel.fitted(to: observations, priorWeight: .nan) == .calibrated)
    }

    // MARK: - 学習の方向

    /// 湿度でだけ体調を崩す人の記録。湿度の重みが上がり、
    /// 同じ湿度条件の確率が汎用より高く出るようになる。
    @Test("湿度に反応する記録は湿度の重みと確率を引き上げる")
    func humiditySensitiveUser() {
        let humid = factors(humidity: 3)
        let stormyButDry = factors(6, baseline: 2)
        let observations =
            Array(repeating: SymptomObservation(factors: humid, wasBad: true), count: 100)
            + Array(repeating: SymptomObservation(factors: stormyButDry, wasBad: false), count: 100)
        let fitted = PersonalRiskModel.fitted(to: observations)

        #expect(fitted.humidity > 1)
        #expect(fitted.humidity > fitted.pressureChange)
        #expect(fitted.probability(of: humid) > PersonalRiskModel.generic.probability(of: humid))
        #expect(fitted.probability(of: stormyButDry)
                < PersonalRiskModel.generic.probability(of: stormyButDry))
        // 通知判定への波及: 汎用では「やや注意」止まり（3pt）の湿度条件が引き上がる。
        #expect(fitted.schedulingLevel(for: humid) > .slight)
    }

    /// 同じ傾向の記録でも、件数が少ないうちは事前分布の近くに留まる（縮小推定）。
    /// n の閾値で挙動が急変しないことが §6.3 改訂の条件。
    @Test("記録が少ないほど事前分布の近くに留まる")
    func fewObservationsStayNearGeneric() {
        func humidityShift(count: Int) -> Double {
            let observations =
                Array(repeating: SymptomObservation(factors: factors(humidity: 3), wasBad: true),
                      count: count)
                + Array(repeating: SymptomObservation(factors: factors(6, baseline: 2), wasBad: false),
                        count: count)
            return abs(PersonalRiskModel.fitted(to: observations).humidity
                       - PersonalRiskModel.calibrated.humidity)
        }
        let small = humidityShift(count: 2)
        let large = humidityShift(count: 100)
        #expect(small < large)
        #expect(small < 0.5)
    }

    /// 「穏やかな日ほど悪い」という記録が来ても、重みは 0 未満へ行かない。
    /// 悪天候で確率が下がる方向の学習は §6.5 の符号制約で禁じている。
    @Test("逆相関の記録でも重みは負にならない")
    func weightsNeverGoNegative() {
        let observations =
            Array(repeating: SymptomObservation(factors: factors(), wasBad: true), count: 100)
            + Array(repeating: SymptomObservation(factors: factors(8, baseline: 3, humidity: 3),
                                                  wasBad: false), count: 100)
        let fitted = PersonalRiskModel.fitted(to: observations)
        for weight in [fitted.pressureChange, fitted.pressureBaseline, fitted.humidity,
                       fitted.precipitation, fitted.temperature] {
            #expect(weight >= 0)
        }
    }

    // MARK: - 体質の事前申告（§6.5）

    @Test("申告なしの事前分布は較正済みモデルと同一になる")
    func emptyDeclarationIsCalibrated() {
        #expect(PersonalRiskModel.prior(for: []) == .calibrated)
    }

    /// 気象要因は独立ではない（雨の日は高湿で、気圧の変化を伴う）。
    /// 申告は主要因を大きく、気象的に相関する要因を小さく傾ける。
    @Test("申告は主要因を大きく、相関する要因を小さく傾ける")
    func declarationTiltsMainAndRelatedWeights() {
        let base = PersonalRiskModel.calibrated
        let humid = PersonalRiskModel.prior(for: [.humidity])
        #expect(humid.humidity == base.humidity + PersonalRiskModel.declarationTilt)
        #expect(humid.precipitation == base.precipitation + PersonalRiskModel.relatedTilt)
        #expect(humid.pressureChange == base.pressureChange && humid.temperature == base.temperature)
        #expect(humid.intercept == base.intercept)

        let rain = PersonalRiskModel.prior(for: [.rain])
        #expect(rain.precipitation == base.precipitation + PersonalRiskModel.declarationTilt)
        #expect(rain.humidity == base.humidity + PersonalRiskModel.relatedTilt)
        #expect(rain.pressureChange == base.pressureChange + PersonalRiskModel.relatedTilt)
        #expect(rain.temperature == base.temperature)

        let pressure = PersonalRiskModel.prior(for: [.pressure])
        #expect(pressure.pressureChange == base.pressureChange + PersonalRiskModel.declarationTilt)
        #expect(pressure.pressureBaseline == base.pressureBaseline + PersonalRiskModel.declarationTilt)
        #expect(pressure.humidity == base.humidity)

        // 複数申告は加算。クランプ範囲 [0, 3] を超えない組み合わせであること。
        let all = PersonalRiskModel.prior(for: Set(DeclaredSensitivity.allCases))
        for weight in [all.pressureChange, all.pressureBaseline, all.humidity,
                       all.precipitation, all.temperature] {
            #expect(weight <= PersonalRiskModel.weightRange.upperBound)
        }
    }

    /// 申告の価値は記録ゼロの初日から通知閾値に効くこと。
    /// 湿度 2pt は較正済みでも「やや注意」止まりだが、湿気の申告があれば「注意」へ上がる。
    @Test("申告だけの初日から通知判定が変わる")
    func declarationTakesEffectFromDayZero() {
        let declared = PersonalRiskModel.prior(for: [.humidity])
        #expect(PersonalRiskModel.fitted(to: [], prior: declared) == declared)

        let humid = factors(humidity: 2)
        #expect(PersonalRiskModel.calibrated.schedulingLevel(for: humid) == .slight)
        #expect(declared.schedulingLevel(for: humid) == .caution)
    }

    /// 申告は初期値であって真実ではない。湿気に弱いと申告していても、
    /// 記録がそれを支持しなければ重みは申告値から引き下げられる。
    @Test("記録は誤った申告を上書きする")
    func recordsOverrideWrongDeclaration() {
        let declared = PersonalRiskModel.prior(for: [.humidity])
        let observations =
            Array(repeating: SymptomObservation(factors: factors(6, baseline: 2), wasBad: true),
                  count: 100)
            + Array(repeating: SymptomObservation(factors: factors(humidity: 3), wasBad: false),
                    count: 100)
        let fitted = PersonalRiskModel.fitted(to: observations, prior: declared)
        #expect(fitted.humidity < declared.humidity)
        #expect(fitted.pressureChange > PersonalRiskModel.calibrated.pressureChange)
    }

    // MARK: - 頑健性

    @Test("同じ記録からは同じモデルが学習される")
    func fittingIsDeterministic() {
        let observations = (0..<50).map { index in
            SymptomObservation(factors: factors(index % 9, humidity: index % 4),
                               wasBad: index % 3 == 0)
        }
        #expect(PersonalRiskModel.fitted(to: observations)
                == PersonalRiskModel.fitted(to: observations))
    }

    /// クランプ範囲の端のモデルでは倍精度の sigmoid が 1.0 へ飽和しうるので、
    /// 表明は閉区間。開区間が必要なのは学習の途中計算ではなく出力の利用側で、
    /// そちらは確率をレベルとの比較にしか使わない。
    @Test("確率は常に0以上1以下で有限に収まる")
    func probabilityStaysInRange() {
        let extreme = PersonalRiskModel(pressureChange: 3, pressureBaseline: 3, humidity: 3,
                                        precipitation: 3, temperature: 3, intercept: 2)
        let floor = PersonalRiskModel(pressureChange: 0, pressureBaseline: 0, humidity: 0,
                                      precipitation: 0, temperature: 0, intercept: -10)
        for model in [PersonalRiskModel.generic, extreme, floor] {
            for f in [factors(), factors(8, baseline: 3, humidity: 3,
                                         precipitation: 2, temperature: 2)] {
                let p = model.probability(of: f)
                #expect(p.isFinite)
                #expect(p >= 0 && p <= 1)
            }
        }
    }

    /// 全記録が同一ラベルという偏った入力でも、クランプにより有限に収まる。
    @Test("全件同一ラベルでも学習が破綻しない")
    func uniformLabelsStayFinite() {
        let allBad = Array(repeating: SymptomObservation(factors: factors(2), wasBad: true),
                           count: 200)
        let fitted = PersonalRiskModel.fitted(to: allBad)
        #expect(fitted.intercept.isFinite)
        #expect(PersonalRiskModel.interceptRange.contains(fitted.intercept))
        let p = fitted.probability(of: factors(2))
        #expect(p > 0 && p < 1)
    }
}
