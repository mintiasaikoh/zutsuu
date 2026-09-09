// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/PersonalRisk/PersonalRiskModel.swift
// 体調記録から学習するロジスティック回帰と、通知閾値の個人化判定。
// 汎用スコアを事前分布にした縮小推定で、記録ゼロでも挙動を変えないため。
// 関連: ../RiskEngine/RiskFactors.swift, docs/personalrisk-api.md, 設計書 §6.5
import Foundation
import RiskEngine

/// 学習の 1 標本。体調記録 1 件と、その時刻の気象から算出した要因点数の組。
/// 要因への変換と時刻の突き合わせはアプリ層が行う（`HealthCheckIn.date` と
/// 同時刻の `WeatherPoint` から `RiskAnalyzer` 相当の点数を得る）。
public struct SymptomObservation: Sendable, Hashable {
    public let factors: RiskFactors
    /// 記録時点で体調が「悪い」だったか。
    public let wasBad: Bool

    public init(factors: RiskFactors, wasBad: Bool) {
        self.factors = factors
        self.wasBad = wasBad
    }
}

/// 「今後の気象条件で体調が悪くなる確率」を返すロジスティック回帰。
///
/// logit = Σ 重み_i × 要因点数_i + 切片。`.generic` は全重み 1・切片 −4 で、
/// 合計 4pt（「注意」境界）ちょうどで確率 0.5 になる。つまり汎用スコアの
/// 順序をそのまま確率へ写した形が事前分布であり、学習はそこからの補正になる。
///
/// **適用先は通知閾値の補正のみ**（設計書 §6.5）。画面のリスクレベル表示は
/// 汎用の `RiskAssessment` を使い続けること。
public struct PersonalRiskModel: Sendable, Equatable {
    /// 各重みは「その要因 1pt が logit に寄与する量」。汎用は全要因 1。
    public let pressureChange: Double
    public let pressureBaseline: Double
    public let humidity: Double
    public let precipitation: Double
    public let temperature: Double
    public let intercept: Double

    /// 重みの許容範囲。下限 0 は「悪天候ほど安全」という方向の学習を禁じる
    /// 符号制約（設計書 §6.5 の安全弁）。上限 3 は 1 要因への過剰適合を抑える。
    public static let weightRange: ClosedRange<Double> = 0...3
    /// 切片の許容範囲。学習データが全て同一ラベルでも確率が 0/1 に張り付かない広さ。
    public static let interceptRange: ClosedRange<Double> = -10...2

    /// 汎用スコアと同じ判定を返すモデル。記録ゼロの状態はこれと完全一致する。
    public static let generic = PersonalRiskModel(
        pressureChange: 1, pressureBaseline: 1, humidity: 1,
        precipitation: 1, temperature: 1, intercept: -4)

    public init(pressureChange: Double, pressureBaseline: Double, humidity: Double,
                precipitation: Double, temperature: Double, intercept: Double) {
        self.pressureChange = pressureChange
        self.pressureBaseline = pressureBaseline
        self.humidity = humidity
        self.precipitation = precipitation
        self.temperature = temperature
        self.intercept = intercept
    }

    /// その要因点数で体調が悪くなる確率（0〜1）。
    public func probability(of factors: RiskFactors) -> Double {
        sigmoid(logit(factors))
    }

    /// 通知判定に使う個人化レベル。**表示には使わないこと。**
    ///
    /// 境界は汎用モデルにおける合計 1・4・7pt の確率と同一式で算出するため、
    /// `.generic` では全ての要因組み合わせで汎用のレベル変換（§3.6）と一致する。
    /// 学習後は同じ確率の物差しの上で境界が個人側へ動く。
    public func schedulingLevel(for factors: RiskFactors) -> RiskLevel {
        let probability = probability(of: factors)
        if probability >= Self.dangerCutoff { return .danger }
        if probability >= Self.cautionCutoff { return .caution }
        if probability >= Self.slightCutoff { return .slight }
        return .calm
    }

    /// 汎用モデルで合計 7pt / 4pt / 1pt に相当する確率。
    /// `probability(of:)` と同じ式で計算するため、境界の等号まで汎用と一致する。
    static let dangerCutoff = sigmoid(7 - 4)
    static let cautionCutoff = sigmoid(4 - 4)
    static let slightCutoff = sigmoid(1 - 4)

    func logit(_ factors: RiskFactors) -> Double {
        pressureChange * Double(factors.pressureChange)
            + pressureBaseline * Double(factors.pressureBaseline)
            + humidity * Double(factors.humidity)
            + precipitation * Double(factors.precipitation)
            + temperature * Double(factors.temperature)
            + intercept
    }
}

private func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

/// オンボーディングで本人が申告する体質（設計書 §6.5）。
///
/// 申告は本人の中で定数なので説明変数にはなれない（切片と共線して情報を持たない）。
/// `PersonalRiskModel.prior(for:)` で事前分布の中心を傾けるためだけに使う。
/// **申告は初期値、記録が真実** — 記録が溜まれば縮小推定が申告を上書きする。
public enum DeclaredSensitivity: String, Codable, Sendable, Hashable, CaseIterable {
    /// 低気圧・気圧の変化に弱い。気圧変化と気圧ベースラインの両方を傾ける。
    case pressure
    /// 雨の日に弱い。
    case rain
    /// 湿気に弱い。
    case humidity
    /// 寒暖差に弱い。
    case temperatureSwing
}

extension PersonalRiskModel {
    /// 申告 1 件が事前重みを引き上げる量（1 → 1.75）。
    /// クランプ上限 3 の内側に収まり、記録による上書きの余地を十分残す設計値。
    /// 実データでの検証は priorWeight と同じく v1.1 有効化前の宿題（正典 §6）。
    public static let declarationTilt = 0.75

    /// 体質申告から事前分布モデルを作る。申告なしなら `.generic` と同一。
    public static func prior(for sensitivities: Set<DeclaredSensitivity>) -> PersonalRiskModel {
        func tilt(_ sensitivity: DeclaredSensitivity) -> Double {
            sensitivities.contains(sensitivity) ? 1 + declarationTilt : 1
        }
        return PersonalRiskModel(pressureChange: tilt(.pressure),
                                 pressureBaseline: tilt(.pressure),
                                 humidity: tilt(.humidity),
                                 precipitation: tilt(.rain),
                                 temperature: tilt(.temperatureSwing),
                                 intercept: generic.intercept)
    }

    /// 事前分布を中心に置いた MAP 推定（L2 罰則付きロジスティック回帰）。
    ///
    /// `prior` の既定は `.generic`（汎用スコアと同じ判定）。体質申告があるときは
    /// `prior(for:)` の結果を渡す。`priorWeight` は事前分布の強さで、擬似観測数として
    /// 読める。既定 24 は「記録が 1 か月弱溜まった頃にデータと事前分布が拮抗する」重さ。
    /// 観測ゼロなら勾配がゼロなので事前分布をそのまま返す（＝申告だけの初日から効く）。
    /// `priorWeight` が非正・非有限のときも事前分布へ倒す。
    ///
    /// 学習は射影勾配降下。決定的（乱数・並列なし）で、同じ入力は同じモデルを返す。
    /// 反復数固定なので実行時間は観測数に比例し、数百件でもミリ秒台に収まる。
    public static func fitted(to observations: [SymptomObservation],
                              prior priorModel: PersonalRiskModel = .generic,
                              priorWeight: Double = 24) -> PersonalRiskModel {
        let prior = priorModel.clamped().parameters
        var parameters = prior
        guard !observations.isEmpty, priorWeight.isFinite, priorWeight > 0 else {
            return priorModel.clamped()
        }

        let samples = observations.map { observation in
            (x: features(of: observation.factors), y: observation.wasBad ? 1.0 : 0.0)
        }
        // ロジスティック損失のヘッセ行列は Σ‖x‖²/4 + priorWeight で上から抑えられる。
        // その逆数を学習率にすると発散しない（保守的だが決定的に安全）。
        let curvature = samples.reduce(priorWeight) { bound, sample in
            bound + sample.x.reduce(0) { $0 + $1 * $1 } / 4
        }
        let learningRate = 1 / curvature

        for _ in 0..<2000 {
            var gradient = parameters.indices.map { (parameters[$0] - prior[$0]) * priorWeight }
            for sample in samples {
                let logit = zip(parameters, sample.x).reduce(0) { $0 + $1.0 * $1.1 }
                let error = sigmoid(logit) - sample.y
                for index in gradient.indices { gradient[index] += error * sample.x[index] }
            }
            for index in parameters.indices {
                let range = index < 5 ? weightRange : interceptRange
                parameters[index] = min(max(parameters[index] - learningRate * gradient[index],
                                            range.lowerBound), range.upperBound)
            }
        }
        return PersonalRiskModel(pressureChange: parameters[0], pressureBaseline: parameters[1],
                                 humidity: parameters[2], precipitation: parameters[3],
                                 temperature: parameters[4], intercept: parameters[5])
    }

    private var parameters: [Double] {
        [pressureChange, pressureBaseline, humidity, precipitation, temperature, intercept]
    }

    /// 全パラメータを許容範囲へ収める。範囲外の事前分布を渡されても
    /// 学習の出発点と縮小の中心が安全弁の内側に留まるようにする。
    private func clamped() -> PersonalRiskModel {
        func weight(_ value: Double) -> Double {
            min(max(value, Self.weightRange.lowerBound), Self.weightRange.upperBound)
        }
        return PersonalRiskModel(
            pressureChange: weight(pressureChange), pressureBaseline: weight(pressureBaseline),
            humidity: weight(humidity), precipitation: weight(precipitation),
            temperature: weight(temperature),
            intercept: min(max(intercept, Self.interceptRange.lowerBound),
                           Self.interceptRange.upperBound))
    }

    private static func features(of factors: RiskFactors) -> [Double] {
        [Double(factors.pressureChange), Double(factors.pressureBaseline),
         Double(factors.humidity), Double(factors.precipitation),
         Double(factors.temperature), 1]
    }
}
