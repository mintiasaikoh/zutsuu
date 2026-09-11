// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/RecordButton.swift
// 「げんき」「ふつう」「つらい」の記録ボタン。
// 全画面版と短い版で同じ見た目・同じアクセシビリティラベルにするため。
// 3 つは同じ色（2026-09-11 ユーザー決定）。塗りつぶしで「つらい」へ誘導しない。
// 関連: KiabouCheckInView.swift, KiabouQuickCheckIn.swift, CheckInModel.swift
#if os(iOS) || os(macOS)
import SwiftUI

struct RecordButton: View {
    let title: String
    let feeling: HealthFeeling
    let palette: KiabouPalette
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.primary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(String(localized: "いまの調子は\(title)。記録する", bundle: .module))
    }
}
#endif
