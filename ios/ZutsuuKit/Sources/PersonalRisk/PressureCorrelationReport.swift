// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/PersonalRisk/PressureCorrelationReport.swift
// 記録から「気圧が動いていたとき／穏やかなとき」の「つらい」の割合を数える記述レポート。
// 最小サンプル数に満たないうちは出さず、出すときも記述に留める（設計書 §6.3）ため。
// 関連: PersonalRiskModel.swift, docs/personalrisk-api.md §2, 設計書 §6.2
import Foundation
import RiskEngine

/// 気圧のみ × 記録の単純な相関レポート（設計書 v1.0）。予測はしない。
public enum PressureCorrelationReport: Sendable, Equatable {
    /// 記録日数がこれ未満なら出さない。設計書 §6.3 の下限（30〜60 日）を設計値として採用。
    public static let minimumRecordedDays = 30

    case insufficient(remainingDays: Int)
    case ready(Summary)

    public struct Summary: Sendable, Equatable {
        /// 気圧が動いていた（気圧変化か絶対気圧の点数が 1 以上）記録の件数と、そのうち「つらい」の件数。
        public let activeCount: Int
        public let activeBad: Int
        /// 気圧が穏やかだった記録の件数と、そのうち「つらい」の件数。
        public let calmCount: Int
        public let calmBad: Int

        public var activeRate: Double? { activeCount > 0 ? Double(activeBad) / Double(activeCount) : nil }
        public var calmRate: Double? { calmCount > 0 ? Double(calmBad) / Double(calmCount) : nil }
    }

    public static func make(observations: [SymptomObservation], recordedDays: Int) -> PressureCorrelationReport {
        guard recordedDays >= minimumRecordedDays else {
            return .insufficient(remainingDays: minimumRecordedDays - max(recordedDays, 0))
        }
        var summary = (activeCount: 0, activeBad: 0, calmCount: 0, calmBad: 0)
        for observation in observations {
            let active = observation.factors.pressureChange > 0 || observation.factors.pressureBaseline > 0
            if active {
                summary.activeCount += 1
                if observation.wasBad { summary.activeBad += 1 }
            } else {
                summary.calmCount += 1
                if observation.wasBad { summary.calmBad += 1 }
            }
        }
        return .ready(Summary(activeCount: summary.activeCount, activeBad: summary.activeBad,
                              calmCount: summary.calmCount, calmBad: summary.calmBad))
    }
}
