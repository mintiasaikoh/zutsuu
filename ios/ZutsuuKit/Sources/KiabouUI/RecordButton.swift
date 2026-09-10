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
                .background(background, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(feeling == .bad ? palette.onPrimary : palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("体調が\(title)。記録する")
    }

    /// 「悪い」だけ塗りつぶし。休む姿へ切り替わる唯一の選択肢なので、視覚的にも際立たせる。
    private var background: Color {
        switch feeling {
        case .bad: palette.primary
        case .normal: palette.primary.opacity(0.16)
        case .good: palette.primary.opacity(0.08)
        }
    }
}
#endif
