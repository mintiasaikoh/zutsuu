// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/RecordWeatherText.swift
// 記録ログの各行に添える、その時の天気の特徴の要約。
// 「あの日はどんな天気だったか」を数値と要因名で淡々と示すため（記述主義、設計書 §6.3）。
// 関連: CheckInStore.swift, KiabouTabView.swift, ../../ZutsuuKit/Sources/AppCore/AlertNotifications.swift
import Foundation
import AppCore
import RiskEngine

enum RecordWeatherText {
    /// 例: 「注意 · 1,004 hPa · 3時間で6hPa低下 · 湿度85% · 降水確率80% · 18℃」。
    /// 生値のない古い記録は要因名だけ（「気圧の変化 · 高い湿度」）。要因の無い記録は nil。
    static func summary(for record: CheckInRecord) -> String? {
        guard record.hasFactors else { return nil }
        var parts: [String] = []
        if let level = record.levelRaw.flatMap(RiskLevel.init(rawValue:)) {
            parts.append(level.displayName)
        }
        if let pressure = record.pressureHPa {
            parts.append("\(Int(pressure.rounded())) hPa")
        }
        if let change = record.pressureChange3h, abs(change).rounded() >= 1 {
            parts.append("3時間で\(Int(abs(change).rounded()))hPa\(change < 0 ? "低下" : "上昇")")
        } else if record.pressureChange > 0 {
            parts.append("気圧の変化")
        }
        if record.pressureBaseline > 0 {
            parts.append("この土地では低い気圧")
        }
        if record.humidity > 0 {
            parts.append(record.humidityPercent.map { "湿度\(Int($0.rounded()))%" } ?? "高い湿度")
        }
        if record.precipitation > 0 {
            parts.append(record.precipitationChance.map { "降水確率\(Int($0.rounded()))%" } ?? "降水")
        }
        if record.temperature > 0 {
            parts.append("気温の急な変化")
        }
        if let celsius = record.temperatureC {
            parts.append("\(Int(celsius.rounded()))℃")
        }
        return parts.isEmpty ? "大きな変化なし" : parts.joined(separator: " · ")
    }
}
