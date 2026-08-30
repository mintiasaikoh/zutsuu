import Foundation

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
