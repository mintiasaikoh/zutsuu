// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/NeutralClimatology.swift
// 気圧平年値テーブル（Plan 6）ができるまでの暫定 PressureClimatology。
// 絶対気圧スコアを常に 0 にする劣化を、黙ってではなく型として明示するため。
// 関連: ../RiskEngine/PressureClimatology.swift, docs/appcore-api.md, 設計書 §5.1
import RiskEngine

/// 常にパーセンタイル 0.5 を返す。絶対気圧スコア（最大 3pt）は恒久的に 0 になる。
///
/// Plan 6 の NOAA 再解析テーブルが入るまでの穴埋め。名前で暫定であることが
/// 分かるようにしてあり、アプリ層がこれを使っている間は 18pt 満点のうち
/// 15pt しか動かない。この事実は `docs/appcore-api.md` に明記する。
public struct NeutralClimatology: PressureClimatology {
    public init() {}

    public func percentile(pressure: Double, coordinate: Coordinate, month: Int) -> Double {
        0.5
    }
}
