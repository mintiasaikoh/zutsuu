import RiskEngine

/// `PressureClimatology` は public API（アプリ層が実装を注入する唯一の口）。
/// ここを素の `import` にしておくことで、`public` の付け忘れをビルドが検出する。
struct StubClimatology: PressureClimatology {
    let value: Double
    func percentile(pressure: Double, latitude: Double, longitude: Double, month: Int) -> Double {
        value
    }
}
