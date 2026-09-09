// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/AppCoreTests/TemperatureSwingDetectorTests.swift
// 日境界の切り出しと欠損時の扱いを検証する。
// 仕様書 §2.1 で「アプリ層が決めること」とされた 3 点の決定を固定するため。
// 関連: ../../Sources/AppCore/TemperatureSwingDetector.swift
import Testing
import Foundation
import AppCore
import RiskEngine

@Suite("寒暖差の生成")
struct TemperatureSwingDetectorTests {

    /// 3/9 は最高 12℃、3/10 は最高 20℃。差 +8 で警告。
    private var twoDays: [WeatherPoint] {
        (0..<48).map { hour in
            let date = utc(9).addingTimeInterval(TimeInterval(hour) * 3600)
            let temperature = hour < 24 ? 12 - Double(abs(hour - 12)) / 3 : 20 - Double(abs(hour - 36)) / 3
            return point(date, temperature: temperature)
        }
    }

    @Test("昨日と今日の最高気温を比較する")
    func comparesDailyMaxima() throws {
        let swing = try #require(TemperatureSwingDetector.detect(in: twoDays, now: utc(10, 8),
                                                                 calendar: utcCalendar))
        #expect(swing.yesterdayMax == 12)
        #expect(swing.todayMax == 20)
        #expect(swing.difference == 8)
        #expect(swing.hasAlert)
    }

    /// 「昨日のデータがない」は寒暖差なしとは別の状態。nil で区別する。
    @Test("昨日の点がなければ nil")
    func nilWithoutYesterday() {
        let todayOnly = twoDays.filter { $0.date >= utc(10) }
        #expect(TemperatureSwingDetector.detect(in: todayOnly, now: utc(10, 8),
                                                calendar: utcCalendar) == nil)
        #expect(TemperatureSwingDetector.detect(in: [], now: utc(10, 8),
                                                calendar: utcCalendar) == nil)
    }

    /// 日境界は渡したカレンダーのタイムゾーンで切る。UTC 3/9 23:00 は東京では
    /// 3/10 08:00 なので「今日」に入り、東京の今日の最高気温は 3/9 23:00 UTC の点を含む。
    @Test("日境界はカレンダーのタイムゾーンで切られる")
    func dayBoundaryFollowsCalendar() throws {
        // 3/9 23:00 UTC だけ突出して 30℃。
        let series = twoDays.map { $0.date == utc(9, 23) ? point($0.date, temperature: 30) : $0 }
        let inUTC = try #require(TemperatureSwingDetector.detect(in: series, now: utc(10, 8),
                                                                 calendar: utcCalendar))
        #expect(inUTC.yesterdayMax == 30)
        #expect(inUTC.todayMax == 20)

        // 東京の 3/10 は UTC 3/9 15:00 〜 3/10 15:00。30℃ の点は今日側。
        let inTokyo = try #require(TemperatureSwingDetector.detect(in: series, now: utc(10, 8),
                                                                   calendar: tokyoCalendar))
        #expect(inTokyo.todayMax == 30)
        #expect(inTokyo.yesterdayMax < 30)
    }

    @Test("今日の最高気温は系列にある範囲だけから取る")
    func todayMaxUsesAvailablePoints() throws {
        let untilNoon = twoDays.filter { $0.date < utc(10, 12) }
        let swing = try #require(TemperatureSwingDetector.detect(in: untilNoon, now: utc(10, 8),
                                                                 calendar: utcCalendar))
        // 正午までなら 3/10 12:00 は含まれない。11:00 の値が最大。
        #expect(swing.todayMax < 20)
    }
}
