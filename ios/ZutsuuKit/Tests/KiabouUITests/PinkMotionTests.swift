// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/KiabouUITests/PinkMotionTests.swift
// 1/fゆらぎの出力範囲と、経過時間・強さの更新規則を検証する。
// 揺れが画面外へ飛んだり、中断復帰で位置が跳ねたりしないことを固定するため。
// 関連: ../../Sources/KiabouUI/PinkMotion.swift
import Testing
import Foundation
@testable import KiabouUI

@Suite("1/fゆらぎ")
struct PinkMotionTests {

    @Test("出力はどの時刻でも[-1, 1]に収まる")
    func boundedOutput() {
        let wave = PinkWave(seed: 42)
        for time in stride(from: 0.0, through: 600.0, by: 0.5) {
            let value = wave.sample(at: time)
            #expect(value >= -1 && value <= 1, "time=\(time) value=\(value)")
        }
    }

    @Test("同じシードは同じ波形を作る")
    func deterministicForSeed() {
        let first = PinkWave(seed: 7)
        let second = PinkWave(seed: 7)
        for time in [0.0, 1.5, 100.0, 3600.0] {
            #expect(first.sample(at: time) == second.sample(at: time))
        }
    }

    @Test("非有限・非正のdeltaと停止中は状態を進めない")
    func advanceGuards() {
        var motion = PinkMotion(seed: 1)
        motion.advance(delta: .nan, enabled: true, resting: false)
        motion.advance(delta: -1, enabled: true, resting: false)
        motion.advance(delta: 0, enabled: true, resting: false)
        motion.advance(delta: 1, enabled: false, resting: false)
        #expect(motion.time == 0)
        #expect(motion.strength == 0)
    }

    /// バックグラウンド滞在や重いフレームの実時間をまとめて適用すると
    /// 復帰時に位置が飛ぶ。1回の進みは 0.1 秒までに切り詰める。
    @Test("大きなdeltaは0.1秒に切り詰めて適用する")
    func clampsLargeDelta() {
        var motion = PinkMotion(seed: 1)
        motion.advance(delta: 5, enabled: true, resting: false)
        #expect(motion.time == 0.1)
    }

    @Test("強さは活動時1、休息時0.3へ漸近する")
    func strengthApproachesTargets() {
        var motion = PinkMotion(seed: 1)
        for _ in 0..<600 { motion.advance(delta: 0.1, enabled: true, resting: false) }
        #expect(abs(motion.strength - 1) < 0.01)
        for _ in 0..<600 { motion.advance(delta: 0.1, enabled: true, resting: true) }
        #expect(abs(motion.strength - 0.3) < 0.01)
    }
}
