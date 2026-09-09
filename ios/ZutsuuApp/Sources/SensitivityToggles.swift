// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/SensitivityToggles.swift
// 体質申告（低気圧・雨・湿気・寒暖差）のトグル群。設定画面とオンボーディングで共用。
// 申告の保存形式（rawValue の配列）を 1 箇所に閉じ込め、AppSettings.load と一致させるため。
// 関連: AppSettings.swift, SettingsView.swift, OnboardingView.swift, 設計書 §6.5
import SwiftUI
import PersonalRisk

struct SensitivityToggles: View {
    /// 選択が変わるたびに呼ぶ（設定画面では予約の更新に使う）。
    var onChange: () -> Void = {}
    @State private var selected: Set<DeclaredSensitivity> = SensitivityToggles.load()

    var body: some View {
        ForEach(DeclaredSensitivity.allCases, id: \.self) { sensitivity in
            Toggle(sensitivity.label, isOn: binding(for: sensitivity))
        }
    }

    private func binding(for sensitivity: DeclaredSensitivity) -> Binding<Bool> {
        Binding(
            get: { selected.contains(sensitivity) },
            set: { isOn in
                if isOn { selected.insert(sensitivity) } else { selected.remove(sensitivity) }
                let names = DeclaredSensitivity.allCases.filter(selected.contains).map(\.rawValue)
                UserDefaults.standard.set(names, forKey: SettingsKey.sensitivities)
                onChange()
            })
    }

    private static func load() -> Set<DeclaredSensitivity> {
        Set((UserDefaults.standard.stringArray(forKey: SettingsKey.sensitivities) ?? [])
            .compactMap(DeclaredSensitivity.init(rawValue:)))
    }
}

extension DeclaredSensitivity {
    var label: String {
        switch self {
        case .pressure: "低気圧・気圧の変化"
        case .rain: "雨の日"
        case .humidity: "湿気"
        case .temperatureSwing: "寒暖差"
        }
    }
}
