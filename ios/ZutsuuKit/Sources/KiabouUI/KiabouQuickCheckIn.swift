// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouQuickCheckIn.swift
// ホーム画面に埋め込む短い記録ビュー。ステージ・2 ボタン・状態・累計日数だけを持つ。
// 起動 2 秒で記録できる動線をホームに置くため（設計原則 §1.3、設計書 §6.1）。
// 関連: KiabouCheckInView.swift, CheckInModel.swift, RecordButton.swift, docs/kiabou-integration.md
#if os(iOS) || os(macOS)
import SwiftUI

/// `KiabouCheckInView` の短い版。見え方の設定は持たず、保存済みの値を読むだけ。
/// `recordedDays` は記録の見返り（累計の記録日数）。nil なら出さない。
public struct KiabouQuickCheckIn: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("kiabou.native.cove") private var cove = true
    @AppStorage("kiabou.native.dim") private var dim = false
    @State private var model: CheckInModel
    private let recordedDays: Int?
    private let showsStage: Bool

    /// `showsStage: false` は背面遊泳モード用。きあぼうが二匹に見えないよう
    /// カード内のステージを隠し、ボタンと状態だけにする（kiabou-integration.md §3.1）。
    public init(recordedDays: Int? = nil, showsStage: Bool = true,
                onRecord: @escaping @MainActor (HealthCheckIn) async throws -> Void) {
        self.recordedDays = recordedDays
        self.showsStage = showsStage
        _model = State(initialValue: CheckInModel(save: onRecord))
    }

    private var palette: KiabouPalette { KiabouPalette(dim: dim) }

    public var body: some View {
        VStack(spacing: 12) {
            if showsStage {
                KiabouStage(resting: model.isResting, cove: cove, dim: dim,
                            moving: !reduceMotion && scenePhase == .active)
                    // ホームの above the fold に「今のリスク → 次の通知 → 記録ボタン」を収める高さ。
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            if model.isResting {
                Text("体調を記録しました。ゆっくり、休んでね。")
                    .foregroundStyle(palette.muted)
                Button("体調の入力に戻る") { model.returnToCheckIn() }
                    .frame(minHeight: 44)
            } else {
                Text("いまの体調は？").font(.headline)
                HStack(spacing: 12) {
                    RecordButton(title: "良い", feeling: .good, palette: palette,
                                 disabled: model.isSaving) { Task { await model.record(.good) } }
                    RecordButton(title: "悪い", feeling: .bad, palette: palette,
                                 disabled: model.isSaving) { Task { await model.record(.bad) } }
                }
                if model.isSaving {
                    Text("記録しています…").foregroundStyle(palette.muted)
                } else if model.lastRecord != nil && model.errorMessage == nil {
                    Text("体調を記録しました。").foregroundStyle(palette.muted)
                }
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(palette.ink).multilineTextAlignment(.center)
            }
            if let recordedDays, recordedDays > 0 {
                Text("記録 \(recordedDays) 日目")
                    .font(.footnote.monospacedDigit()).foregroundStyle(palette.muted)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.ink)
        .tint(palette.primary)
    }
}
#endif
