// /Users/mymac/zutsuu/ios/ZutsuuKit/Tests/AppCoreTests/ReanalysisClimatologyTests.swift
// 同梱テーブルの読み込み・境界の一致・地域差の妥当性を検証する。
// 「テーブルが壊れていても静かに 0.5 を返す」を防ぎ、絶対気圧スコアが本当に動くことを固定するため。
// 関連: ../../Sources/AppCore/ReanalysisClimatology.swift, tools/climatology/show_points.py
import Testing
import Foundation
import RiskEngine
@testable import AppCore

@Suite("気圧平年値テーブル")
struct ReanalysisClimatologyTests {
    let tokyo = Coordinate(latitude: 35.68, longitude: 139.77)
    let reykjavik = Coordinate(latitude: 64.13, longitude: -21.9)
    let ulaanbaatar = Coordinate(latitude: 47.92, longitude: 106.92)
    let singapore = Coordinate(latitude: 1.35, longitude: 103.82)

    @Test("同梱テーブルが読み込める")
    func bundledLoads() throws {
        _ = try ReanalysisClimatology.bundled()
    }

    @Test("壊れたデータは受け付けない")
    func rejectsBadData() {
        #expect(throws: ClimatologyTableError.badHeader) { try ReanalysisClimatology(data: Data()) }
        var short = Data("ZSLP".utf8)
        short.append(Data(repeating: 0, count: 20))
        #expect(throws: (any Error).self) { try ReanalysisClimatology(data: short) }
    }

    @Test("境界ちょうどで0.10・0.25・0.40を返し、気圧に対して単調で0〜1に収まる")
    func cutsAndMonotonic() throws {
        let table = try ReanalysisClimatology.bundled()
        let cuts = table.thresholds(coordinate: tokyo, month: 1)
        #expect(cuts.p10 < cuts.p25 && cuts.p25 < cuts.p40)
        #expect(abs(table.percentile(pressure: cuts.p10, coordinate: tokyo, month: 1) - 0.10) < 1e-9)
        #expect(abs(table.percentile(pressure: cuts.p25, coordinate: tokyo, month: 1) - 0.25) < 1e-9)
        #expect(abs(table.percentile(pressure: cuts.p40, coordinate: tokyo, month: 1) - 0.40) < 1e-9)
        var previous = -1.0
        for tenth in 9500...10500 {
            let p = table.percentile(pressure: Double(tenth) / 10, coordinate: tokyo, month: 1)
            #expect(p >= 0 && p <= 1 && p.isFinite)
            #expect(p >= previous)
            previous = p
        }
        #expect(table.percentile(pressure: .nan, coordinate: tokyo, month: 1) == 0.5)
    }

    /// 設計書 §5.1 の動機: 冬の内陸高緯度は常に高く、熱帯は分布が狭い。固定閾値 1005 では破綻する。
    @Test("地域差: 冬のウランバートルの下位10%は東京の下位40%より高く、シンガポールの幅は狭い")
    func regionalSanity() throws {
        let table = try ReanalysisClimatology.bundled()
        let tokyoJan = table.thresholds(coordinate: tokyo, month: 1)
        let ulaanbaatarJan = table.thresholds(coordinate: ulaanbaatar, month: 1)
        let singaporeJan = table.thresholds(coordinate: singapore, month: 1)
        let reykjavikJan = table.thresholds(coordinate: reykjavik, month: 1)
        #expect(ulaanbaatarJan.p10 > tokyoJan.p40)
        #expect(singaporeJan.p40 - singaporeJan.p10 < reykjavikJan.p40 - reykjavikJan.p10)
        #expect(tokyoJan.p25 > 1000 && tokyoJan.p25 < 1030)
        // 1005 hPa は東京の冬なら「低い」（+2 以上）が、レイキャビクの冬では普通。
        #expect(table.percentile(pressure: 1005, coordinate: tokyo, month: 1) < 0.25)
        #expect(table.percentile(pressure: 1005, coordinate: reykjavik, month: 1) > 0.40)
    }

    @Test("月と経度の端は巻き戻し、緯度は範囲に収める")
    func edgesAreHandled() throws {
        let table = try ReanalysisClimatology.bundled()
        let a = table.thresholds(coordinate: Coordinate(latitude: 35.68, longitude: 139.77), month: 13)
        let b = table.thresholds(coordinate: Coordinate(latitude: 35.68, longitude: 139.77 - 360), month: 1)
        #expect(a == b)
        let dateline = table.thresholds(coordinate: Coordinate(latitude: 0, longitude: 179.9), month: 6)
        #expect(dateline.p10.isFinite)
        let pole = table.thresholds(coordinate: Coordinate(latitude: -95, longitude: 0), month: 6)
        #expect(pole.p10.isFinite)
    }
}
