// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/RecordButton.swift
// 「良い」「悪い」の記録ボタン。
// 全画面版と短い版で同じ見た目・同じアクセシビリティラベルにするため。
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
                .background(feeling == .bad ? palette.primary : palette.primary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(feeling == .bad ? palette.onPrimary : palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("体調が\(title)。記録する")
    }
}
#endif
