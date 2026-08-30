import Testing
import RiskEngine

@Suite("寒暖差検知")
struct TemperatureSwingTests {

    @Test("前日比5℃以上でアラート")
    func swingAlertFires() {
        let swing = TemperatureSwing(todayMax: 25, yesterdayMax: 19)
        #expect(swing.difference == 6)
        #expect(swing.hasAlert)
    }

    @Test("5℃ちょうどでアラート、4.9℃では出ない")
    func swingBoundary() {
        #expect(TemperatureSwing(todayMax: 25, yesterdayMax: 20).hasAlert)
        #expect(!TemperatureSwing(todayMax: 24.9, yesterdayMax: 20).hasAlert)
    }

    @Test("急に冷え込む場合もアラートになる")
    func swingHandlesDrop() {
        let swing = TemperatureSwing(todayMax: 15, yesterdayMax: 23)
        #expect(swing.difference == -8)
        #expect(swing.hasAlert)
    }

    /// 前日と同じならアラートは出ない。閾値定数の移植値も固定する。
    @Test("差がなければアラートは出ない")
    func swingNoChange() {
        let swing = TemperatureSwing(todayMax: 20, yesterdayMax: 20)
        #expect(swing.difference == 0)
        #expect(!swing.hasAlert)
        #expect(TemperatureSwing.threshold == 5)
    }

    /// 冷え込み側の境界も上昇側と同じ 5℃ で切れることを固定する。
    /// `abs` を外すと -5 が通らなくなり、ここが落ちる。
    @Test("冷え込み側の境界も5℃ちょうどで切れる")
    func swingDropBoundary() {
        #expect(TemperatureSwing(todayMax: 15, yesterdayMax: 20).hasAlert)
        #expect(!TemperatureSwing(todayMax: 15.1, yesterdayMax: 20).hasAlert)
    }
}
