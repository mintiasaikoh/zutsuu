// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/PinkMotion.swift
// 帯域を限った1/fゆらぎと、一時停止できる経過時間を管理する。
// 休む姿の揺れを小さくし、復帰時に位置を飛ばさないため。
// 関連: KiabouScene.swift, ../../../../assets/kiabou/fluctuation.js, PinkMotionTests.swift
import Foundation

/// 対数周波数に等パワーを配り、0.025–0.4 Hz内でPSD ≈ 1/fを作る。
/// 総和を成分数で割るため、出力はどの時刻でも[-1, 1]以内。
struct PinkWave {
    private let waves: [(frequency: Double, phase: Double)]

    init(seed: UInt32) {
        var state = seed
        func random() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / 4_294_967_296
        }
        waves = (0..<96).map { index in
            (0.025 * pow(16, (Double(index) + random()) / 96), random() * .pi * 2)
        }
    }

    func sample(at time: Double) -> Double {
        waves.reduce(0) { $0 + sin(2 * .pi * $1.frequency * time + $1.phase) } / 96
    }
}

struct PinkMotion {
    let horizontal: PinkWave
    let vertical: PinkWave
    let tilt: PinkWave
    private(set) var time = 0.0
    private(set) var strength = 0.0

    init(seed: UInt32 = .random(in: .min ... .max)) {
        horizontal = PinkWave(seed: seed)
        vertical = PinkWave(seed: seed &+ 1)
        tilt = PinkWave(seed: seed &+ 2)
    }

    mutating func advance(delta: Double, enabled: Bool, resting: Bool) {
        guard enabled, delta.isFinite, delta > 0 else { return }
        // 中断や重いフレームの実時間をまとめて適用しない。
        let dt = min(delta, 0.1)
        time += dt
        strength += ((resting ? 0.3 : 1) - strength) * (1 - exp(-dt / 1.5))
    }
}
