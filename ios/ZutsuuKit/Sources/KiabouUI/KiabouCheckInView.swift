// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouCheckInView.swift
// 1タップ体調入力と、本人が選んできあぼうと休む画面（全画面版。アプリ未使用、watchOS 向けに保持）。
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
    @AppStorage("kiabou.pillow") private var pillowID = KiabouBedding.matchID
    @AppStorage("kiabou.blanket") private var blanketID = KiabouBedding.matchID
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
                    Text("きあぼう", bundle: .module).font(.subheadline.weight(.medium)).foregroundStyle(palette.muted)
                    Text(model.isResting ? "ゆっくり、休んでね。" : "いまの調子は？", bundle: .module)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                    Text(model.isResting ? "きあぼうも、ここで休んでいます。" : "ひとつ押すだけで、記録できます。", bundle: .module)
                        .font(.body).foregroundStyle(palette.muted)
                }
                .multilineTextAlignment(.center)

                KiabouStage(resting: model.isResting, scenery: .scenery(id: sceneID), dim: dim,
                            moving: motionEnabled && scenePhase == .active,
                            outfit: .outfit(id: outfitID),
                            bedding: KiabouBedding(pillow: pillowID, blanket: blanketID))
                    .frame(height: 300)
                    .padding(.horizontal, -24)

                if model.isResting {
                    Text("このまま、画面を閉じて大丈夫。", bundle: .module)
                        .multilineTextAlignment(.center).foregroundStyle(palette.muted)
                    Button {
                        model.returnToCheckIn()
                        headingFocused = true
                    } label: { Text("もどる", bundle: .module) }
                    .frame(minHeight: 44)
                } else {
                    HStack(spacing: 10) {
                        ForEach(HealthFeeling.allCases, id: \.self) { feeling in
                            RecordButton(title: feeling.label, feeling: feeling, palette: palette,
                                         disabled: model.isSaving) { Task { await model.record(feeling) } }
                        }
                    }
                    if model.isSaving {
                        Text("記録しています…", bundle: .module).foregroundStyle(palette.muted)
                    } else if model.lastRecord != nil && model.errorMessage == nil {
                        Text("記録したよ。", bundle: .module)
                            .foregroundStyle(palette.muted).accessibilityAddTraits(.updatesFrequently)
                    }
                    Button {
                        model.rest()
                        headingFocused = true
                    } label: { Text("きあぼうと寝る", bundle: .module) }
                    .frame(minHeight: 44)
                    .accessibilityHint(String(localized: "きあぼうが毛布にくるまって休みます。記録はしません", bundle: .module))
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(palette.ink).multilineTextAlignment(.center)
                }

                Button {
                    motionOverride = !motionEnabled
                } label: { Text(motionEnabled ? "ゆらぎを止める" : "ゆらぎを動かす", bundle: .module) }
                .frame(minHeight: 44)

                VStack(spacing: 16) {
                    Toggle(isOn: $dim) { Text("薄明かり", bundle: .module) }
                }
                .toggleStyle(.switch)
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "見え方", bundle: .module))
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
