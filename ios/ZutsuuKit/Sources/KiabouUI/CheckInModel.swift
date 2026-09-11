// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/CheckInModel.swift
// 体調の保存完了と、本人が選ぶ休む表示を管理する。
// 保存失敗を成功と見せず、休む・戻るの表示操作を記録にしないため。
// 関連: HealthCheckIn.swift, KiabouCheckInView.swift, CheckInModelTests.swift
import Foundation
import Observation

@MainActor @Observable
final class CheckInModel {
    private(set) var isSaving = false
    private(set) var isResting = false
    private(set) var lastRecord: HealthCheckIn?
    private(set) var errorMessage: String?
    private var pendingRecord: HealthCheckIn?
    private let save: @MainActor (HealthCheckIn) async throws -> Void

    init(save: @escaping @MainActor (HealthCheckIn) async throws -> Void) {
        self.save = save
    }

    func record(_ feeling: HealthFeeling) async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        // 保存結果が不明な再試行にも同じID・時刻を渡し、ホスト側の重複防止に使う。
        let entry = pendingRecord?.feeling == feeling ? pendingRecord! : HealthCheckIn(feeling: feeling)
        pendingRecord = entry
        defer { isSaving = false }
        do {
            try await save(entry)
            lastRecord = entry
            pendingRecord = nil
            // 記録は休む姿を切り替えない（2026-09-11）。休むかは本人が rest() で選ぶ。
        } catch {
            errorMessage = String(localized: "記録できませんでした。もう一度お試しください。", bundle: .module)
        }
    }

    /// 「きあぼうと寝る」。表示の切り替えで、体調は保存しない。
    func rest() {
        isResting = true
    }

    func returnToCheckIn() {
        isResting = false
        // これは表示の切り替え。体調の「良い」を保存してはいけない。
    }
}
