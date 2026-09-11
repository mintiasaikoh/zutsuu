// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouCheckInView.swift
// 1タップ体調入力と、記録後にきあぼうと休む画面。
// 個人化につながる体調記録を中心に、静かな背景と相棒を統合するため。
// 関連: CheckInModel.swift, KiabouStage.swift, HealthCheckIn.swift, docs/kiabou-integration.md
#if os(iOS) || os(macOS)
import SwiftUI

/// `onRecord`はアプリの保存処理に接続する。正常終了したときだけ記録完了を表示する。
/// 同じIDの再試行を重複保存しないこと。気象データとの関連付け・学習はアプリ層が担う。
public struct KiabouCheckInView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("kiabou.scene") private var sceneID = KiabouScenery.cove.id
    @AppStorage("kiabou.native.dim") private var dim = false
    @AppStorage("kiabou.outfit") private var outfitID = KiabouOutfit.original.id
    @State private var model: CheckInModel
    @State private var motionOverride: Bool?
    @AccessibilityFocusState private var headingFocused: Bool

    public init(onRecord: @escaping @MainActor (HealthCheckIn) async throws -> Void) {
        _model = State(initialValue: CheckInModel(save: onRecord))
    }

    private var palette: KiabouPalette { KiabouPalette(dim: dim) }
    private var motionEnabled: Bool { motionOverride ?? !reduceMotion }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text("きあぼう").font(.subheadline.weight(.medium)).foregroundStyle(palette.muted)
                    Text(model.isResting ? "ゆっくり、休んでね。" : "いまの調子は？")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                    Text(model.isResting ? "きあぼうも、ここで休んでいます。" : "ひとつ押すだけで、記録できます。")
                        .font(.body).foregroundStyle(palette.muted)
                }
                .multilineTextAlignment(.center)

                KiabouStage(resting: model.isResting, scenery: .scenery(id: sceneID), dim: dim,
                            moving: motionEnabled && scenePhase == .active,
                            outfit: .outfit(id: outfitID))
                    .frame(height: 300)
                    .padding(.horizontal, -24)

                if model.isResting {
                    Text("このまま、画面を閉じて大丈夫。")
                        .multilineTextAlignment(.center).foregroundStyle(palette.muted)
                    Button("もどる") {
                        model.returnToCheckIn()
                        headingFocused = true
                    }
                    .frame(minHeight: 44)
                } else {
                    HStack(spacing: 10) {
                        ForEach(HealthFeeling.allCases, id: \.self) { feeling in
                            RecordButton(title: feeling.label, feeling: feeling, palette: palette,
                                         disabled: model.isSaving) { Task { await model.record(feeling) } }
                        }
                    }
                    if model.isSaving {
                        Text("記録しています…").foregroundStyle(palette.muted)
                    } else if model.lastRecord != nil && model.errorMessage == nil {
                        Text("記録したよ。")
                            .foregroundStyle(palette.muted).accessibilityAddTraits(.updatesFrequently)
                    }
                    Button("きあぼうと寝る") {
                        model.rest()
                        headingFocused = true
                    }
                    .frame(minHeight: 44)
                    .accessibilityHint("きあぼうが毛布にくるまって休みます。記録はしません")
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(palette.ink).multilineTextAlignment(.center)
                }

                Button(motionEnabled ? "ゆらぎを止める" : "ゆらぎを動かす") {
                    motionOverride = !motionEnabled
                }
                .frame(minHeight: 44)

                VStack(spacing: 16) {
                    Toggle("薄明かり", isOn: $dim)
                }
                .toggleStyle(.switch)
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("見え方")
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(palette.page.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .tint(palette.primary)
        .preferredColorScheme(dim ? .dark : .light)
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { motionOverride = false }
        }
        .onChange(of: model.isResting) { _, _ in headingFocused = true }
    }

}
#endif
