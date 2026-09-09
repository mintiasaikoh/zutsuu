// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouPalette.swift
// 入り江の背景に合わせた昼・薄明かりの配色を定義する。
// 背景を暗くしても文字と操作の読みやすさを保ち、アプリ全体で同じ 3 色 + 紙白を使うため。
// 関連: KiabouCheckInView.swift, KiabouStage.swift, assets/kiabou/scenery.css
#if os(iOS) || os(macOS)
import SwiftUI

/// きあぼうの世界の配色。3 色（文字・強調・控えめ）+ 紙白の規律で、アプリ全体が共有する。
public struct KiabouPalette: Sendable {
    public let dim: Bool

    public init(dim: Bool) {
        self.dim = dim
    }

    public var page: Color { color(dim ? 0x26343d : 0xf2f4f1) }
    public var card: Color { color(dim ? 0x2f3f49 : 0xffffff) }
    public var ink: Color { color(dim ? 0xe0e7e9 : 0x273e50) }
    public var muted: Color { color(dim ? 0xb9c6cc : 0x526775) }
    public var primary: Color { color(dim ? 0xbdcfd6 : 0x254c69) }
    public var onPrimary: Color { color(dim ? 0x203541 : 0xffffff) }

    private func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 255) / 255,
              green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}
#endif
