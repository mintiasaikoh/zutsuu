// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/AppCoreTests/WatchPayloadTests.swift
// Watch との往復ペイロードの符号化と、古い要約を使わない判定を検証する。
// 端末間で形式がずれると記録が黙って落ちるため、往復とバージョンを固定する。
// 関連: ../../Sources/AppCore/WatchPayload.swift, docs/plans/2026-09-12-watchos-plan5.md
import Testing
import Foundation
import RiskEngine
@testable import AppCore

@Suite("Watch ペイロード")
struct WatchPayloadTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("要約は往復しても等しく、バージョンを持つ")
    func contextRoundTrip() throws {
        let context = WatchContext(updatedAt: base,
                                   hourly: [.init(date: base, level: .caution),
                                            .init(date: base.addingTimeInterval(3600), level: .calm)],
                                   nextAlertTitle: "気圧が下がります", recordedDays: 12)
        let decoded = try WatchContext.decode(try context.encoded())
        #expect(decoded == context)
        #expect(decoded.version == WatchContext.currentVersion)
    }

    @Test("時刻に対応する時間帯のレベルを返し、6時間より古い要約は nil")
    func levelLookup() {
        let context = WatchContext(updatedAt: base,
                                   hourly: [.init(date: base, level: .caution)],
                                   nextAlertTitle: nil, recordedDays: 0)
        #expect(context.level(at: base.addingTimeInterval(1800)) == .caution)
        #expect(context.level(at: base.addingTimeInterval(3600)) == nil)
        #expect(context.level(at: base.addingTimeInterval(WatchContext.staleAfter)) == nil)
    }

    @Test("記録は id・時刻・体調を保ったまま往復する")
    func checkInRoundTrip() throws {
        let checkIn = WatchCheckIn(id: UUID(), date: base, feeling: "bad")
        #expect(try WatchCheckIn.decode(try checkIn.encoded()) == checkIn)
    }
}
