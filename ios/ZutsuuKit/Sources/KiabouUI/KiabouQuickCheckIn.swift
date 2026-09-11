// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouQuickCheckIn.swift
// ホーム画面に埋め込む短い記録ビュー。ステージ・3 ボタン・寝るボタン・状態・累計日数だけを持つ。
// 起動 2 秒で記録できる動線をホームに置くため（設計原則 §1.3、設計書 §6.1）。
// 関連: KiabouCheckInView.swift, CheckInModel.swift, RecordButton.swift, docs/kiabou-integration.md
#if os(iOS) || os(macOS)
import SwiftUI

/// `KiabouCheckInView` の短い版。見え方の設定は持たず、保存済みの値を読むだけ。
/// `recordedDays` は記録の見返り（累計の記録日数）。nil なら出さない。
public struct KiabouQuickCheckIn: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("kiabou.scene") private var sceneID = KiabouScenery.cove.id
    @AppStorage("kiabou.native.dim") private var dim = false
    @AppStorage("kiabou.outfit") private var outfitID = KiabouOutfit.original.id
    @AppStorage("kiabou.pillow") private var pillowID = KiabouBedding.matchID
    @AppStorage("kiabou.blanket") private var blanketID = KiabouBedding.matchID
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
                KiabouStage(resting: model.isResting, scenery: .scenery(id: sceneID), dim: dim,
                            moving: !reduceMotion && scenePhase == .active,
                            outfit: .outfit(id: outfitID),
                            bedding: KiabouBedding(pillow: pillowID, blanket: blanketID))
                    // ホームの above the fold に「今のリスク → 次の通知 → 記録ボタン」を収める高さ。
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            if model.isResting {
                Text("ゆっくり、休んでね。")
                    .foregroundStyle(palette.muted)
                Button("もどる") { model.returnToCheckIn() }
                    .frame(minHeight: 44)
            } else {
                Text("いまの調子は？").font(.headline)
                HStack(spacing: 10) {
                    ForEach(HealthFeeling.allCases, id: \.self) { feeling in
                        RecordButton(title: feeling.label, feeling: feeling, palette: palette,
                                     disabled: model.isSaving) { Task { await model.record(feeling) } }
                    }
                }
                if model.isSaving {
                    Text("記録しています…").foregroundStyle(palette.muted)
                } else if model.lastRecord != nil && model.errorMessage == nil {
                    Text("記録したよ。").foregroundStyle(palette.muted)
                }
                // 休むかは本人が選ぶ。記録とは独立の表示操作（kiabou-integration.md §2）。
                Button("きあぼうと寝る") { model.rest() }
                    .frame(minHeight: 44)
                    .accessibilityHint("きあぼうが毛布にくるまって休みます。記録はしません")
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
