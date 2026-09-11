// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/KiabouUITests/CheckInModelTests.swift
// 体調記録の保存状態遷移を、保存の成否と再試行を軸に検証する。
// 保存失敗を成功と見せない・再試行を重複記録にしない約束を固定するため。
// 関連: ../../Sources/KiabouUI/CheckInModel.swift, ../../Sources/KiabouUI/HealthCheckIn.swift
import Testing
import Foundation
@testable import KiabouUI

@MainActor
private final class SaveSpy {
    private(set) var attempts: [HealthCheckIn] = []
    var failure: (any Error)?

    func save(_ entry: HealthCheckIn) async throws {
        attempts.append(entry)
        if let failure { throw failure }
    }
}

private struct SaveError: Error {}

@MainActor
@Suite("体調記録の状態管理")
struct CheckInModelTests {

    /// 記録は休む姿を切り替えない（2026-09-11）。「つらい」でも泳ぐ姿のまま。
    @Test("保存成功で記録が確定し、どの体調でも休む表示にはならない")
    func successfulSave() async {
        let spy = SaveSpy()
        let model = CheckInModel(save: spy.save)

        await model.record(.bad)
        #expect(spy.attempts.map(\.feeling) == [.bad])
        #expect(model.lastRecord?.feeling == .bad)
        #expect(!model.isResting)
        #expect(model.errorMessage == nil)

        await model.record(.good)
        #expect(spy.attempts.map(\.feeling) == [.bad, .good])
        #expect(!model.isResting)
    }

    /// 休むのは本人が「きあぼうと寝る」を押したときだけ。記録操作ではない。
    @Test("「きあぼうと寝る」は記録を保存せずに休む表示へ切り替える")
    func restDoesNotSave() async {
        let spy = SaveSpy()
        let model = CheckInModel(save: spy.save)

        model.rest()
        #expect(model.isResting)
        #expect(spy.attempts.isEmpty)
        #expect(model.lastRecord == nil)
    }

    @Test("保存失敗は成功と表示せず、エラーメッセージを出す")
    func failedSave() async {
        let spy = SaveSpy()
        spy.failure = SaveError()
        let model = CheckInModel(save: spy.save)

        await model.record(.bad)
        #expect(model.lastRecord == nil)
        #expect(!model.isResting)
        #expect(model.errorMessage != nil)
    }

    /// 保存結果が不明なまま再試行した場合、ホスト側が重複を弾けるように
    /// 同じ ID・時刻を渡し直す。成功するまで entry を作り直してはいけない。
    @Test("同じ体調の再試行は同じIDと時刻で保存される")
    func retryReusesEntry() async {
        let spy = SaveSpy()
        spy.failure = SaveError()
        let model = CheckInModel(save: spy.save)

        await model.record(.bad)
        spy.failure = nil
        await model.record(.bad)

        #expect(spy.attempts.count == 2)
        #expect(spy.attempts[0].id == spy.attempts[1].id)
        #expect(spy.attempts[0].date == spy.attempts[1].date)
        #expect(model.lastRecord?.id == spy.attempts[0].id)
    }

    @Test("失敗後に別の体調を選んだら新しい記録として保存される")
    func changedFeelingMakesNewEntry() async {
        let spy = SaveSpy()
        spy.failure = SaveError()
        let model = CheckInModel(save: spy.save)

        await model.record(.bad)
        spy.failure = nil
        await model.record(.good)

        #expect(spy.attempts.count == 2)
        #expect(spy.attempts[0].id != spy.attempts[1].id)
        #expect(model.lastRecord?.feeling == .good)
    }

    /// 「体調の入力に戻る」は表示の切り替えであって記録操作ではない。
    /// ここで「良い」が保存されると、回復していないのに回復扱いになる。
    @Test("入力に戻る操作は新しい記録を保存しない")
    func returnToCheckInDoesNotSave() async {
        let spy = SaveSpy()
        let model = CheckInModel(save: spy.save)

        await model.record(.bad)
        model.rest()
        model.returnToCheckIn()

        #expect(spy.attempts.count == 1)
        #expect(!model.isResting)
        #expect(model.lastRecord?.feeling == .bad)
    }
}
