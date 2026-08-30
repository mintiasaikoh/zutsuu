/// 気圧の変化量スコア（最大 8pt）。
/// 変化量は標高・気候帯によらず同じ意味を持つため、固定閾値のままでよい。
/// 上昇・下降のどちらでも症状が出るため絶対値で評価する。
func pressureChangeScore(_ changes: PressureChanges) -> Int {
    var score = 0

    let abs1h = abs(changes.oneHour)
    if abs1h >= 4 { score += 3 }
    else if abs1h >= 3 { score += 2 }
    else if abs1h >= 2 { score += 1 }

    let abs3h = abs(changes.threeHour)
    if abs3h >= 8 { score += 3 }
    else if abs3h >= 6 { score += 2 }
    else if abs3h >= 4 { score += 1 }

    let abs6h = abs(changes.sixHour)
    if abs6h >= 10 { score += 2 }
    else if abs6h >= 6 { score += 1 }

    return score
}

/// 絶対気圧のスコア（最大 3pt）。
/// 固定閾値ではなく地点別の分布上の位置で評価する。
/// これにより熱帯での常時アラートと高緯度内陸での無発火を同時に解消する。
/// 副次的に高標高地の問題も解決する（分布の相対位置は標高の影響を受けないため）。
/// `percentile` は 0.0〜1.0 の閉じた契約。範囲外・非有限値は実装側のバグ。
///
/// 通知が静かに止まるのを防いでいるのは `isFinite` ガードのほう。
/// NaN は全ての比較が false になるため、ガードが無いとこの関数は 0 を返し続け、
/// 気圧要因が永久に 0 になっても誰も気付けない。
///
/// clamp は現時点では結果を一切変えない（閾値が全て片側 `<` のため、
/// 負値は最初のバケットに、1.0 超は既定値に落ちる）。残してあるのは前方互換のため。
/// この無害性は「閾値が全て片側」という性質に依存しており、それは不変ではない。
/// 例えば高気圧側の規則 `if clamped > 0.90` を足した瞬間に clamp が効き始める。
func absolutePressureScore(percentile: Double) -> Int {
    guard percentile.isFinite else {
        assertionFailure("percentile が有限値でない: \(percentile)")
        return 0
    }
    let clamped = min(max(percentile, 0), 1)
    if clamped < 0.10 { return 3 }
    if clamped < 0.25 { return 2 }
    if clamped < 0.40 { return 1 }
    return 0
}

/// 湿度スコア（最大 3pt）。高湿度と気圧低下が重なる場合にボーナスを加える。
func humidityScore(humidity: Double, pressureChange3h: Double) -> Int {
    var score = 0
    if humidity >= 85 { score += 2 }
    else if humidity >= 75 { score += 1 }
    if humidity >= 75 && pressureChange3h <= -4 { score += 1 }
    return score
}

/// 降水スコア（最大 2pt）。
func precipitationScore(chance: Double, amount: Double) -> Int {
    var score = 0
    if chance >= 80 { score += 2 }
    else if chance >= 60 { score += 1 }
    if amount > 2 && score < 2 { score += 1 }
    return score
}

/// 気温変動スコア（最大 2pt）。3 時間以内の急変を評価する。
func temperatureScore(temperatureChange3h: Double) -> Int {
    let change = abs(temperatureChange3h)
    if change >= 8 { return 2 }
    if change >= 5 { return 1 }
    return 0
}
