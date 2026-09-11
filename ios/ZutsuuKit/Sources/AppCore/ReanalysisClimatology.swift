// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/ReanalysisClimatology.swift
// 同梱の気圧平年値テーブル（NCEP/NCAR 再解析 1991〜2020、2.5° 格子）から、その地点・その月の
// 海面気圧のパーセンタイルを返す。通信なし・遅延ゼロで世界中の絶対気圧スコアを成立させるため（設計書 §5.1）。
// 関連: ../RiskEngine/PressureClimatology.swift, NeutralClimatology.swift,
//       tools/climatology/build_slp_table.py, docs/research/2026-09-12-pressure-climatology.md
import Foundation
import RiskEngine

public enum ClimatologyTableError: Error, Equatable {
    case missingResource
    case badHeader
    case badSize(expected: Int, actual: Int)
}

/// 格子・月ごとの日平均海面気圧の 10・25・40 パーセンタイル値（hPa × 10 の Int16）を持ち、
/// 地点は双一次補間、気圧は境界間の線形補間で 0〜1 に写す。境界ちょうどで 0.10 / 0.25 / 0.40。
/// スコア（§3.2）が見るのはこの 3 境界だけなので、それ以外の区間の値は近似でよい。
public struct ReanalysisClimatology: PressureClimatology, Sendable {
    static let resourceName = "slp-climatology.bin"
    static let latCount = 73
    static let lonCount = 144
    static let statCount = 3
    static let headerSize = 16
    private static let gridStep = 2.5

    private let table: [Int16]

    /// `AppCore` のバンドルから読む。テーブルが壊れていればエラー（呼び出し側は `NeutralClimatology` へ倒す）。
    public static func bundled() throws -> ReanalysisClimatology {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: nil) else {
            throw ClimatologyTableError.missingResource
        }
        return try ReanalysisClimatology(data: try Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let expected = Self.headerSize + 12 * Self.latCount * Self.lonCount * Self.statCount * 2
        guard data.count >= Self.headerSize, data.prefix(4) == Data("ZSLP".utf8) else {
            throw ClimatologyTableError.badHeader
        }
        guard data.count == expected else {
            throw ClimatologyTableError.badSize(expected: expected, actual: data.count)
        }
        let body = data.dropFirst(Self.headerSize)
        table = body.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Int16(littleEndian: $0) }
        }
    }

    public func percentile(pressure: Double, coordinate: Coordinate, month: Int) -> Double {
        guard pressure.isFinite else { return 0.5 }
        let cuts = thresholds(coordinate: coordinate, month: month)
        // 境界間の幅。同値の格子（理論上ありえないが）で割り算が壊れないよう下限を置く。
        let lowSpan = max(cuts.p25 - cuts.p10, 0.1)
        let highSpan = max(cuts.p40 - cuts.p25, 0.1)
        let value: Double
        if pressure < cuts.p10 {
            value = 0.10 - (cuts.p10 - pressure) / lowSpan * 0.15
        } else if pressure < cuts.p25 {
            value = 0.10 + (pressure - cuts.p10) / lowSpan * 0.15
        } else if pressure < cuts.p40 {
            value = 0.25 + (pressure - cuts.p25) / highSpan * 0.15
        } else {
            value = 0.40 + (pressure - cuts.p40) / highSpan * 0.15
        }
        return min(max(value, 0), 1)
    }

    /// その地点・その月の 3 境界（hPa）。格子 4 点の双一次補間。
    func thresholds(coordinate: Coordinate, month: Int) -> (p10: Double, p25: Double, p40: Double) {
        let m = ((max(month, 1) - 1) % 12 + 12) % 12
        let lat = min(max(coordinate.latitude, -90), 90)
        let lon = coordinate.longitude.truncatingRemainder(dividingBy: 360)
        let row = (90 - lat) / Self.gridStep
        let col = ((lon < 0 ? lon + 360 : lon) / Self.gridStep)
        let i0 = min(Int(row.rounded(.down)), Self.latCount - 1)
        let i1 = min(i0 + 1, Self.latCount - 1)
        let j0 = Int(col.rounded(.down)) % Self.lonCount
        let j1 = (j0 + 1) % Self.lonCount
        let fi = row - Double(i0)
        let fj = col - Double(Int(col.rounded(.down)))
        func stat(_ k: Int) -> Double {
            func cell(_ i: Int, _ j: Int) -> Double {
                Double(table[((m * Self.latCount + i) * Self.lonCount + j) * Self.statCount + k]) / 10
            }
            let top = cell(i0, j0) * (1 - fj) + cell(i0, j1) * fj
            let bottom = cell(i1, j0) * (1 - fj) + cell(i1, j1) * fj
            return top * (1 - fi) + bottom * fi
        }
        return (stat(0), stat(1), stat(2))
    }
}
