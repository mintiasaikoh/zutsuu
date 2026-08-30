/// 地点・月ごとの海面気圧の平年分布。
/// 実装は Plan 6 で NOAA 再解析ベースの静的テーブルとして与える。
/// ここで抽象化しておくことで、テーブルが無くてもエンジンを完成させられる。
public protocol PressureClimatology: Sendable {
    /// 与えられた気圧が、その地点・その月の分布上どの位置にあるかを 0.0〜1.0 で返す。
    /// 0.0 に近いほど「その土地としては低い」。
    func percentile(pressure: Double, latitude: Double, longitude: Double, month: Int) -> Double
}
