// /Users/mymac/zutsuu/ios/ZutsuuAds/Tests/AdPolicyTests/AdPolicyTests.swift
// 頻度制御と解放期限を、設計書 §8.2 の数値どおりに固定する。
// 予期しない全画面広告はポリシー違反なので、閾値のずれをテストで防ぐ。
// 関連: ../../Sources/AdPolicy/*.swift, docs/plans/2026-09-12-admob-plan4.md
import Testing
import Foundation
@testable import AdPolicy

@Suite("広告の頻度制御")
struct InterstitialGateTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let gate = InterstitialGate(calendar: Calendar(identifier: .gregorian))

    private func run(_ count: Int, from state: InterstitialGate.State, start: Date, step: TimeInterval = 1)
        -> (shown: [Int], state: InterstitialGate.State) {
        var state = state
        var shown: [Int] = []
        for i in 1...count {
            let r = gate.transition(state, now: start.addingTimeInterval(Double(i) * step))
            state = r.state
            if r.show { shown.append(i) }
        }
        return (shown, state)
    }

    @Test("起動後の最初の遷移では出さず、4回ごとに出る")
    func everyFourthTransition() {
        let r = run(8, from: gate.launched(.init(), now: base), start: base, step: 200)
        #expect(r.shown == [4, 8])
    }

    @Test("前回表示から3分未満なら遷移が溜まっても出さない")
    func minimumInterval() {
        let r = run(8, from: gate.launched(.init(), now: base), start: base, step: 10)
        #expect(r.shown == [4])
    }

    @Test("1日6回で止まり、日付が変わると数え直す")
    func dailyLimit() {
        var state = gate.launched(.init(), now: base)
        var shown = 0
        for i in 1...60 {
            let r = gate.transition(state, now: base.addingTimeInterval(Double(i) * 200))
            state = r.state
            if r.show { shown += 1 }
        }
        #expect(shown == 6)
        let nextDay = base.addingTimeInterval(86_400 + 60_000)
        let r = run(8, from: gate.launched(state, now: nextDay), start: nextDay, step: 200)
        #expect(r.shown == [4, 8])
    }

    @Test("通知経由の起動による遷移は数えない")
    func notificationLaunchDoesNotCount() {
        var state = gate.launched(.init(), now: base)
        for i in 1...10 {
            state = gate.transition(state, now: base.addingTimeInterval(Double(i)), countsAsTransition: false).state
        }
        #expect(state.transitionsSinceLaunch == 0)
        #expect(state.transitionsSinceShown == 0)
    }
}

@Suite("App Open 広告")
struct AppOpenGateTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let gate = AppOpenGate()

    @Test("コールドスタートと通知経由では出さず、復帰は4時間あける")
    func rules() {
        #expect(!gate.shouldShow(lastShown: nil, now: base, isColdStart: true, launchedFromNotification: false))
        #expect(!gate.shouldShow(lastShown: nil, now: base, isColdStart: false, launchedFromNotification: true))
        #expect(gate.shouldShow(lastShown: nil, now: base, isColdStart: false, launchedFromNotification: false))
        #expect(!gate.shouldShow(lastShown: base, now: base.addingTimeInterval(3 * 3600), isColdStart: false, launchedFromNotification: false))
        #expect(gate.shouldShow(lastShown: base, now: base.addingTimeInterval(4 * 3600), isColdStart: false, launchedFromNotification: false))
    }
}

@Suite("リワードの解放期限")
struct RewardUnlocksTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("期限は設計書の表どおりで、期限内だけ解放される")
    func durations() {
        #expect(RewardPerk.correlationReport.duration == 7 * 86_400)
        #expect(RewardPerk.extraLocation.duration == 30 * 86_400)
        #expect(RewardPerk.detailedForecast.duration == 24 * 3600)
        #expect(RewardPerk.logGraph.duration == 7 * 86_400)
        let unlocks = RewardUnlocks().granting(.correlationReport, now: base)
        #expect(unlocks.isUnlocked(.correlationReport, now: base.addingTimeInterval(7 * 86_400 - 1)))
        #expect(!unlocks.isUnlocked(.correlationReport, now: base.addingTimeInterval(7 * 86_400)))
        #expect(!unlocks.isUnlocked(.logGraph, now: base))
        #expect(RewardUnlocks().remaining(.correlationReport, now: base) == nil)
    }

    @Test("再視聴は今からの期間に置き換え、重ね掛けしない")
    func regrantReplaces() {
        let first = RewardUnlocks().granting(.correlationReport, now: base)
        let later = base.addingTimeInterval(3 * 86_400)
        let again = first.granting(.correlationReport, now: later)
        let remaining = again.remaining(.correlationReport, now: later) ?? -1
        #expect(abs(remaining - 7 * 86_400) < 1, "remaining=\(remaining)")
    }

    @Test("保存形式は往復できる")
    func codable() throws {
        let unlocks = RewardUnlocks().granting(.logGraph, now: base)
        let data = try JSONEncoder().encode(unlocks)
        #expect(try JSONDecoder().decode(RewardUnlocks.self, from: data) == unlocks)
    }
}
