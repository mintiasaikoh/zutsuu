// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/AppSettings.swift
// 静穏時間と体質申告の保存キーと読み出し。
// 設定画面（AppStorage）とパイプライン（UserDefaults）が同じキーを参照するため。
// 関連: SettingsView.swift, ForecastPipeline.swift
import Foundation
import PersonalRisk
import RiskEngine

enum SettingsKey {
    static let quietEnabled = "settings.quiet.enabled"
    static let quietStart = "settings.quiet.start"
    static let quietEnd = "settings.quiet.end"
    static let sensitivities = "settings.sensitivities"
}

struct AppSettings {
    let quietHours: QuietHours?
    let sensitivities: Set<DeclaredSensitivity>

    /// 既定は設計書 §4 の 22:00〜08:30、申告なし。
    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        defaults.register(defaults: [
            SettingsKey.quietEnabled: true,
            SettingsKey.quietStart: 22.0,
            SettingsKey.quietEnd: 8.5,
        ])
        let quiet = defaults.bool(forKey: SettingsKey.quietEnabled)
            ? QuietHours(start: defaults.double(forKey: SettingsKey.quietStart),
                         end: defaults.double(forKey: SettingsKey.quietEnd))
            : nil
        let names = defaults.stringArray(forKey: SettingsKey.sensitivities) ?? []
        return AppSettings(quietHours: quiet,
                           sensitivities: Set(names.compactMap(DeclaredSensitivity.init(rawValue:))))
    }
}
