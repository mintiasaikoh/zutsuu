/// 地点の緯度・経度。
///
/// 緯度と経度は同じ `Double` で意味だけが違うため、隣り合う引数として渡すと
/// 取り違えてもコンパイルが通ってしまう。このプロジェクトでは同型の隣接引数による
/// 取り違えが既に 3 度起きている（差分の向きの反転、湿度と降水確率の入れ替え、
/// そして緯度経度そのもの）。テストで押さえるのではなく、型で表現不可能にする。
public struct Coordinate: Sendable, Hashable {
    /// 緯度（度）。北が正。
    public let latitude: Double
    /// 経度（度）。東が正。
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
