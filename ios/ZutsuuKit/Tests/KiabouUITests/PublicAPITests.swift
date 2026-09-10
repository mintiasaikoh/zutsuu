// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/KiabouUITests/PublicAPITests.swift
// 素のimportで公開APIだけを触り、public化の漏れと直列化の安定性を検証する。
// RiskEngineTestsと同じく、素のimportをpublic付け忘れの検出装置にするため。
// 関連: ../../Sources/KiabouUI/HealthCheckIn.swift, ../RiskEngineTests
import Testing
import Foundation
import KiabouUI

@Suite("KiabouUI公開API")
struct PublicAPITests {

    @Test("HealthCheckInはidと時刻を既定で採番し、値で比較できる")
    func healthCheckInDefaults() {
        let entry = HealthCheckIn(feeling: .bad)
        let copy = HealthCheckIn(id: entry.id, date: entry.date, feeling: .bad)
        #expect(copy == entry)
        #expect(entry.id != HealthCheckIn(feeling: .bad).id)
    }

    /// rawValueは保存済みデータの互換キー。変更すると過去の記録が読めなくなる。
    @Test("HealthFeelingのrawValueは安定している")
    func stableRawValues() {
        #expect(HealthFeeling.good.rawValue == "good")
        #expect(HealthFeeling.normal.rawValue == "normal")
        #expect(HealthFeeling.bad.rawValue == "bad")
        // 表示順 = 良い・普通・悪い。ボタンの並びがこの順に依存する。
        #expect(HealthFeeling.allCases == [.good, .normal, .bad])
    }

    @Test("HealthCheckInはCodableで往復できる")
    func codableRoundTrip() throws {
        let entry = HealthCheckIn(feeling: .good)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HealthCheckIn.self, from: data)
        #expect(decoded == entry)
    }
}
