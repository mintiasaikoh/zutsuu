// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/WatchPayload.swift
// iPhone と Apple Watch の間でやり取りする値型。予報の要約（iPhone → Watch）と体調記録（Watch → iPhone）。
// Watch は予報を取らず iPhone の要約だけを映し、記録は iPhone の保存経路へ戻す（Plan 5、設計書 §7.2）ため。
// 関連: ../RiskEngine/RiskLevel.swift, docs/plans/2026-09-12-watchos-plan5.md, docs/appcore-api.md
import Foundation
import RiskEngine

/// iPhone の予報更新ごとに Watch へ送る要約。Tier 0 相当の情報だけを持つ。
public struct WatchContext: Codable, Sendable, Equatable {
    public struct HourLevel: Codable, Sendable, Equatable {
        public let date: Date
        public let level: RiskLevel
        public init(date: Date, level: RiskLevel) {
            self.date = date
            self.level = level
        }
    }

    public static let currentVersion = 1
    /// 更新からこれより古い要約はコンプリケーションが「—」にする（古い予報を今と偽らない）。
    public static let staleAfter: TimeInterval = 6 * 3600

    public let version: Int
    public let updatedAt: Date
    public let hourly: [HourLevel]
    public let nextAlertTitle: String?
    public let recordedDays: Int

    public init(updatedAt: Date, hourly: [HourLevel], nextAlertTitle: String?, recordedDays: Int) {
        version = Self.currentVersion
        self.updatedAt = updatedAt
        self.hourly = hourly
        self.nextAlertTitle = nextAlertTitle
        self.recordedDays = recordedDays
    }

    /// その時刻の時間帯のレベル。要約が古い、または時刻が範囲外なら nil。
    public func level(at date: Date) -> RiskLevel? {
        guard date.timeIntervalSince(updatedAt) < Self.staleAfter else { return nil }
        let hourStart = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        return hourly.first { $0.date == hourStart }?.level
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> WatchContext { try JSONDecoder().decode(WatchContext.self, from: data) }
}

/// Watch で押した体調記録。`id` は iPhone 側の重複防止キー（kiabou-integration.md §2.2）。
/// `feeling` は `HealthFeeling.rawValue`（AppCore は KiabouUI に依存しないため文字列で持つ）。
public struct WatchCheckIn: Codable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let feeling: String

    public init(id: UUID, date: Date, feeling: String) {
        self.id = id
        self.date = date
        self.feeling = feeling
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> WatchCheckIn { try JSONDecoder().decode(WatchCheckIn.self, from: data) }
}

extension RiskLevel: Codable {}
