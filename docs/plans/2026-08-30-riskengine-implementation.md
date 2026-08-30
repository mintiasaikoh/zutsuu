# RiskEngine 実装計画

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 気象データから複合リスクスコアを算出する純粋ロジックを、テスト付きの Swift パッケージとして実装する。

**Architecture:** WeatherKit や UI から完全に独立した Swift Package `ZutsuuKit` を作る。
WeatherKit は iOS 専用で entitlement を要するため、エンジンからは一切参照しない。
代わりに `WeatherPoint` という中立な入力型を定義し、アプリ層が WeatherKit → `WeatherPoint` の変換を担う。
これによりエンジンは macOS 上で `swift test` だけで検証でき、シミュレータ起動が不要になる。

**Tech Stack:** Swift 6.2 / Swift Package Manager / Swift Testing（`import Testing`）

**確認済み環境:** Xcode 26.3、Swift 6.2.4。`swift test`（macOS ネイティブ）、
`xcodebuild -destination 'generic/platform=iOS'`、`generic/platform=watchOS` のいずれもビルド成功を実測済み。

**参照:** [設計書](2026-08-30-global-ios-app-design.md) §5（グローバル対応）、移植元は `src/index.ts:136-190`

---

## 実施記録

| バッチ | タスク | 状態 | コミット |
|---|---|---|---|
| A | Task 1-2 | 完了・レビュー承認済み | `13af292` `1de661a` `7af6963` |
| B | Task 3-6 | 完了・レビュー承認済み | `630b61c` `2873b08` `9a07f21` `d9764de` |
| C | Task 7-8 | 未着手 | |
| D | Task 9-10 | 未着手 | |
| E | Task 11-12 | 未着手 | |

### Batch A のレビューで確定した変更

以下は Task 1-2 の記述と実際のコードの差分。**下流のタスクはこちらが正**。

1. **`RiskEngine` 名前空間 enum と `SmokeTests.swift` は削除した。**
   `public enum RiskEngine` がモジュール名 `RiskEngine` を隠蔽し、`RiskEngine.WeatherPoint` が
   モジュールではなく enum に解決されるため、モジュール修飾による名前衝突の回避が不可能になっていた。
   アプリ層で `WeatherPoint` / `RiskLevel` が SwiftUI・WeatherKit の型名と衝突した際に詰む。

2. **`RiskFactors` は `pressureChange`（0-8）と `pressureBaseline`（0-3）の 2 フィールドに分割した。**
   `pressure` は両者の和を返す computed property。`total` の意味は不変。
   設計書 §5.1 で絶対気圧項の意味が変わったため、UI が「急降下中」と「この土地としては低い」を
   区別できる必要がある。合算後は分離不能。

3. **`PressureChanges`（`oneHour` / `threeHour` / `sixHour`）を追加した。**
   `compositeRisk` の引数に同型 Double が 8 個並ぶのを避けるため。

4. **公開範囲の方針を確定した。**
   スコアリングの自由関数は **internal**。public API は
   ドメイン型・`PressureClimatology`・`RiskAnalyzer`・`AlertScheduler` のみ。
   internal な関数のテストは `@testable import`、public 面のテストは素の `import` を使う。
   素の import は `public` 付け忘れを検出するための仕掛けであり、実際に Batch A で
   `PressureChanges` の init 漏れを検出した。

5. **`WeatherPoint` の単位は `///` doc comment に `- Warning:` 付きで明記した。**
   WeatherKit は湿度・降水確率を 0...1 で提供するがこの型は 0...100 を期待する。
   範囲バリデーションは意図的に入れていない（設計書 §11.6 参照）。

### Batch C で判明した計画の誤り（重大）

**変化量は前方差分でなければならない。本計画の Task 7 に書かれていた後方差分は誤りだった。**

移植元 `src/index.ts:239-242` は前方差分である。

```js
const change1h = i + 1 < n ? p[i + 1] - p[i] : 0;
const change3h = i + 3 < n ? p[i + 3] - p[i] : change1h * 3;
```

つまり「時刻 T の時点で、これから何 hPa 下がるか」を評価している。
計画に書かれていた `index - hoursAgo`（後方差分）は「T までに何 hPa 下がったか」であり、意味が逆。

**なぜ致命的か。** 後方差分ではリスクのピークが気圧降下の**終わり**に来る。
その 90 分前に通知しても降下の真っ最中であり、症状が出始めた後になる。
前方差分ならリスクは降下の**開始時**に立ち、同じ 90 分の先行時間が降下前に着地する。
「薬を飲むタイミングを事前に知らせる」という製品の核が、この符号ひとつで成立しなくなる。

**Task 11 のパリティテストでは検出できない。** あちらは `compositeRisk` を
明示的な変化量で直接呼ぶため、系列からの抽出を一切通らない。

引数ラベルは `hoursAgo:` ではなく **`hoursAhead:`** とする。
方向が名前に現れていなかったことが、この誤りが潜伏できた原因そのものである。

**Task 10 への申し送り（前方差分の副作用）。** 前方差分では、解析対象系列の末尾 6 時間は
前方窓が系列外に出るため、気圧変化スコアが必然的に 0 になる。
72 時間の予報のうち先頭 24 時間を解析する運用ではこれは見えないが、
**スケジューラに「ちょうど解析窓ぶんに切り詰めた系列」を渡すと、末尾が静かに「安心」と読まれる**。
ヘルパー側ではなく呼び出し側でガードすること。

**TS の外挿フォールバックは意図的に採用しない。** TS は前方データが尽きたとき
`change1h * 3` / `change1h * 6` で外挿するが、1 時間の変化から 6 時間の変化を作るのはデータの捏造であり、
外れ通知は見逃しより信頼を損なう。加えて 72 時間の予報のうち先頭 24 時間しか解析しないため、
この分岐は実際にはほぼ到達しない。範囲外は 0 を返す。

---

---

## この計画のスコープ

**含む:** リスクスコアリング、時系列解析、寒暖差検知、通知予約時刻の算出（すべて純粋関数）

**含まない（後続の計画）:**
- Plan 2: Xcode アプリ本体、WeatherKit 接続、通知予約の実行
- Plan 3: SwiftUI 画面と体調記録
- Plan 4: AdMob 統合（4 層モデル）
- Plan 5: watchOS ターゲット
- Plan 6: 気圧平年値テーブルの生成（NOAA 再解析からの変換パイプライン）

**Plan 6 との関係:** 本計画では平年値を `PressureClimatology` プロトコルとして抽象化し、
テストではスタブを注入する。実データのテーブルが無くても全タスクが完了できる。

---

## ディレクトリ構成

```
zutsuu/
├── src/index.ts              ← 既存 LINE 版。触らない
├── ios/
│   └── ZutsuuKit/            ← 本計画で作る
│       ├── Package.swift
│       ├── Sources/RiskEngine/
│       └── Tests/RiskEngineTests/
└── docs/plans/
```

---

### Task 1: Swift Package の骨格

**Files:**
- Create: `ios/ZutsuuKit/Package.swift`
- Create: `ios/ZutsuuKit/Sources/RiskEngine/RiskEngine.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/SmokeTests.swift`

**Step 1: パッケージを作成**

```bash
mkdir -p ios/ZutsuuKit/Sources/RiskEngine ios/ZutsuuKit/Tests/RiskEngineTests
```

`ios/ZutsuuKit/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZutsuuKit",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "RiskEngine", targets: ["RiskEngine"])
    ],
    targets: [
        .target(name: "RiskEngine"),
        .testTarget(name: "RiskEngineTests", dependencies: ["RiskEngine"])
    ]
)
```

`macOS(.v15)` を含めるのが重要。これがないと `swift test` がこの Mac 上で走らない。

**Step 2: 最小のソースとテストを置く**

`Sources/RiskEngine/RiskEngine.swift`:

```swift
public enum RiskEngine {
    public static let version = "0.1.0"
}
```

`Tests/RiskEngineTests/SmokeTests.swift`:

```swift
import Testing
@testable import RiskEngine

@Test("パッケージがビルドできる")
func packageBuilds() {
    #expect(RiskEngine.version == "0.1.0")
}
```

**Step 3: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS（1 test passed）

**Step 4: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: Swift Package の骨格を追加"
```

---

### Task 2: ドメイン型

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/RiskLevel.swift`
- Create: `ios/ZutsuuKit/Sources/RiskEngine/RiskFactors.swift`
- Create: `ios/ZutsuuKit/Sources/RiskEngine/WeatherPoint.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/DomainTypeTests.swift`

**Step 1: 失敗するテストを書く**

```swift
import Testing
import Foundation
@testable import RiskEngine

@Test("リスクレベルは大小比較できる")
func riskLevelIsComparable() {
    #expect(RiskLevel.calm < RiskLevel.danger)
    #expect(RiskLevel.allCases.count == 4)
}

@Test("リスク要因の合計は各要素の和")
func riskFactorsTotal() {
    let f = RiskFactors(pressure: 3, humidity: 2, precipitation: 1, temperature: 2)
    #expect(f.total == 8)
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL（`cannot find 'RiskLevel' in scope`）

**Step 3: 実装する**

`RiskLevel.swift`:

```swift
/// リスクの 4 段階。src/index.ts:16 の定義に合わせている。
/// SPEC.md には 5 段階と書かれているが、そちらが古い。
public enum RiskLevel: Int, Sendable, Comparable, CaseIterable {
    case calm = 1      // 安心
    case slight = 2    // やや注意
    case caution = 3   // 注意
    case danger = 4    // 危険

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

`RiskFactors.swift`:

```swift
public struct RiskFactors: Sendable, Equatable {
    public let pressure: Int
    public let humidity: Int
    public let precipitation: Int
    public let temperature: Int

    public init(pressure: Int, humidity: Int, precipitation: Int, temperature: Int) {
        self.pressure = pressure
        self.humidity = humidity
        self.precipitation = precipitation
        self.temperature = temperature
    }

    public var total: Int { pressure + humidity + precipitation + temperature }
}
```

`WeatherPoint.swift`:

```swift
import Foundation

/// 気象データの中立表現。アプリ層が WeatherKit から変換して渡す。
/// RiskEngine が WeatherKit に依存しないための境界。
public struct WeatherPoint: Sendable, Equatable {
    public let date: Date
    public let pressure: Double            // hPa（海面気圧）
    public let temperature: Double         // ℃
    public let humidity: Double            // %（0〜100）
    public let precipitationChance: Double // %（0〜100）
    public let precipitationAmount: Double // mm

    public init(date: Date, pressure: Double, temperature: Double,
                humidity: Double, precipitationChance: Double, precipitationAmount: Double) {
        self.date = date
        self.pressure = pressure
        self.temperature = temperature
        self.humidity = humidity
        self.precipitationChance = precipitationChance
        self.precipitationAmount = precipitationAmount
    }
}
```

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: ドメイン型を追加"
```

---

### Task 3: 気圧変化スコア

移植元: `src/index.ts:143-155`。1h / 3h / 6h の変化量から最大 8pt。

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/Scoring.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/PressureChangeScoreTests.swift`
- Modify: `ios/ZutsuuKit/Tests/RiskEngineTests/DomainTypeTests.swift`

**Step 1: 失敗するテストを書く**

境界値を必ず両側から突く。`>=` の実装ミスが最も出やすい箇所。
スコアリング関数は internal なので `@testable import` を使う。

```swift
import Testing
@testable import RiskEngine

@Suite("気圧変化スコア")
struct PressureChangeScoreTests {

    @Test("1時間変化のスコア", arguments: [
        (0.0, 0), (1.9, 0), (2.0, 1), (2.9, 1), (3.0, 2), (3.9, 2), (4.0, 3), (10.0, 3)
    ])
    func oneHour(change: Double, expected: Int) {
        let changes = PressureChanges(oneHour: change, threeHour: 0, sixHour: 0)
        #expect(pressureChangeScore(changes) == expected)
    }

    @Test("気圧上昇も下降と同じく評価される")
    func symmetric() {
        let falling = PressureChanges(oneHour: -4, threeHour: 0, sixHour: 0)
        let rising = PressureChanges(oneHour: 4, threeHour: 0, sixHour: 0)
        #expect(pressureChangeScore(falling) == pressureChangeScore(rising))
    }

    @Test("3時間変化のスコア", arguments: [(3.9, 0), (4.0, 1), (6.0, 2), (8.0, 3)])
    func threeHour(change: Double, expected: Int) {
        #expect(pressureChangeScore(PressureChanges(oneHour: 0, threeHour: change, sixHour: 0)) == expected)
    }

    @Test("6時間変化のスコア", arguments: [(5.9, 0), (6.0, 1), (10.0, 2)])
    func sixHour(change: Double, expected: Int) {
        #expect(pressureChangeScore(PressureChanges(oneHour: 0, threeHour: 0, sixHour: change)) == expected)
    }

    @Test("3つの変化量は加算される（最大8pt）")
    func accumulates() {
        #expect(pressureChangeScore(PressureChanges(oneHour: -5, threeHour: -9, sixHour: -12)) == 8)
    }
}
```

あわせて `DomainTypeTests.swift`（素の `import RiskEngine` のまま）に、
`WeatherPoint` の public 面を実際に構築するテストを 1 件足す。
現在この型はテストから一度も構築されておらず、`public` 付け忘れが検出できない状態になっている。

```swift
@Test("WeatherPointはモジュール外から構築できる")
func weatherPointIsPubliclyConstructible() {
    let point = WeatherPoint(date: Date(timeIntervalSince1970: 0), pressure: 1013,
                             temperature: 20, humidity: 60,
                             precipitationChance: 30, precipitationAmount: 0)
    #expect(point.humidity == 60)
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL（`cannot find 'pressureChangeScore' in scope`）

**Step 3: 実装する**

`Scoring.swift`:

```swift
import Foundation

/// 気圧の変化量スコア（最大 8pt）。
/// 変化量は標高・気候帯によらず同じ意味を持つため、固定閾値のままでよい。
/// 上昇・下降のどちらでも症状が出るため絶対値で評価する。
func pressureChangeScore(_ changes: PressureChanges) -> Int {
    var score = 0

    let abs1h = abs(changes.oneHour)
    if abs1h >= 4 { score += 3 }
    else if abs1h >= 3 { score += 2 }
    else if abs1h >= 2 { score += 1 }

    let abs3h = abs(changes.threeHour)
    if abs3h >= 8 { score += 3 }
    else if abs3h >= 6 { score += 2 }
    else if abs3h >= 4 { score += 1 }

    let abs6h = abs(changes.sixHour)
    if abs6h >= 10 { score += 2 }
    else if abs6h >= 6 { score += 1 }

    return score
}
```

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 気圧変化スコアを実装"
```

---

### Task 4: 絶対気圧スコア（パーセンタイル方式）

設計書 §5.1 の核心。固定閾値 `pressure <= 1005`（`src/index.ts:159-161`）を置き換える。

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/PressureClimatology.swift`
- Modify: `ios/ZutsuuKit/Sources/RiskEngine/Scoring.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/AbsolutePressureScoreTests.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/TestHelpers.swift`

**Step 1: 失敗するテストを書く**

`TestHelpers.swift`（以降のバッチでも使う）:

```swift
import Foundation
@testable import RiskEngine

struct StubClimatology: PressureClimatology {
    let value: Double
    func percentile(pressure: Double, latitude: Double, longitude: Double, month: Int) -> Double {
        value
    }
}
```

`AbsolutePressureScoreTests.swift`:

```swift
import Testing
@testable import RiskEngine

@Suite("絶対気圧スコア")
struct AbsolutePressureScoreTests {

    @Test("パーセンタイルからスコアへの変換", arguments: [
        (0.05, 3), (0.099, 3), (0.10, 2), (0.24, 2), (0.25, 1), (0.39, 1), (0.40, 0), (0.90, 0)
    ])
    func conversion(percentile: Double, expected: Int) {
        #expect(absolutePressureScore(percentile: percentile) == expected)
    }

    /// 設計書 §5.1 の破綻ケース。固定閾値では熱帯が常時アラートになっていた。
    @Test("熱帯の平常時の気圧はアラートにならない")
    func tropicalNormalIsCalm() {
        let climatology = StubClimatology(value: 0.50)
        let p = climatology.percentile(pressure: 1008, latitude: 1.35, longitude: 103.8, month: 7)
        #expect(absolutePressureScore(percentile: p) == 0)
    }

    /// 固定閾値では 1030hPa 常態の地域が永久に発火しなかった。
    @Test("高緯度内陸でも相対的に低ければ発火する")
    func highLatitudeRelativeLowFires() {
        let climatology = StubClimatology(value: 0.05)
        let p = climatology.percentile(pressure: 1015, latitude: 47.9, longitude: 106.9, month: 1)
        #expect(absolutePressureScore(percentile: p) == 3)
    }
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL（`cannot find 'absolutePressureScore' in scope`）

**Step 3: 実装する**

`PressureClimatology.swift`（public。アプリ層が実装を注入するため）:

```swift
/// 地点・月ごとの海面気圧の平年分布。
/// 実装は Plan 6 で NOAA 再解析ベースの静的テーブルとして与える。
/// ここで抽象化しておくことで、テーブルが無くてもエンジンを完成させられる。
public protocol PressureClimatology: Sendable {
    /// 与えられた気圧が、その地点・その月の分布上どの位置にあるかを 0.0〜1.0 で返す。
    /// 0.0 に近いほど「その土地としては低い」。
    func percentile(pressure: Double, latitude: Double, longitude: Double, month: Int) -> Double
}
```

`Scoring.swift` に追記:

```swift
/// 絶対気圧のスコア（最大 3pt）。
/// 固定閾値ではなく地点別の分布上の位置で評価する。
/// これにより熱帯での常時アラートと高緯度内陸での無発火を同時に解消する。
/// 副次的に高標高地の問題も解決する（分布の相対位置は標高の影響を受けないため）。
func absolutePressureScore(percentile: Double) -> Int {
    guard percentile.isFinite else {
        assertionFailure("percentile が有限値でない: \(percentile)")
        return 0
    }
    let clamped = min(max(percentile, 0), 1)
    if clamped < 0.10 { return 3 }
    if clamped < 0.25 { return 2 }
    if clamped < 0.40 { return 1 }
    return 0
}
```

**記録の訂正:** クランプ行は現時点では全ての有限 `Double` に対して **no-op** である。
閾値がすべて片側 `<` のため、負値は元から `< 0.10` に落ち、1 を超える値は元から素通りして 0 を返す。
有限値 4,000,019 点（各閾値の `nextDown`、`±greatestFiniteMagnitude`、`-0.0` を含む）の
全数掃引で差分ゼロを確認済み。**クランプを「テストで守られた防御」として数えてはならない。**

実際に効いているのは `isFinite` ガードのみである。修正前は `.nan` が静かに 0 を返し、
気圧要因が恒久的に 0 になって通知が止まる状態だった。

クランプ自体は残す。no-op である性質は「全閾値が片側 `<` であること」に依存しており、
これは安定した前提ではない。高気圧側のルール（例 `if clamped > 0.90`）を足した瞬間に効き始める。

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 絶対気圧をパーセンタイル方式で評価"
```

---

### Task 5: 湿度・降水・気温スコア

移植元: `src/index.ts:163-180`。3 つとも単純なので 1 タスクにまとめる。

**Files:**
- Modify: `ios/ZutsuuKit/Sources/RiskEngine/Scoring.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/OtherScoreTests.swift`

**Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import RiskEngine

@Suite("湿度・降水・気温スコア")
struct OtherScoreTests {

    @Test("湿度スコア", arguments: [(74.0, 0), (75.0, 1), (84.0, 1), (85.0, 2), (100.0, 2)])
    func humidity(value: Double, expected: Int) {
        #expect(humidityScore(humidity: value, pressureChange3h: 0) == expected)
    }

    @Test("高湿度と気圧低下が重なるとボーナス1pt")
    func humidityPressureCombo() {
        #expect(humidityScore(humidity: 80, pressureChange3h: -4) == 2)
        #expect(humidityScore(humidity: 80, pressureChange3h: -3.9) == 1)  // 閾値未満
        #expect(humidityScore(humidity: 74, pressureChange3h: -10) == 0)   // 湿度が足りない
        #expect(humidityScore(humidity: 90, pressureChange3h: -5) == 3)    // 上限 3pt
    }

    @Test("降水スコア", arguments: [(59.0, 0), (60.0, 1), (79.0, 1), (80.0, 2), (100.0, 2)])
    func precipitation(chance: Double, expected: Int) {
        #expect(precipitationScore(chance: chance, amount: 0) == expected)
    }

    @Test("降水量が多いと加点されるが上限は2pt")
    func precipitationAmountBonus() {
        #expect(precipitationScore(chance: 0, amount: 3) == 1)
        #expect(precipitationScore(chance: 0, amount: 2) == 0)   // 2mm ちょうどは加点しない
        #expect(precipitationScore(chance: 90, amount: 10) == 2) // 上限で頭打ち
    }

    @Test("気温変動スコア", arguments: [(0.0, 0), (4.9, 0), (5.0, 1), (7.9, 1), (8.0, 2), (-8.0, 2)])
    func temperature(change: Double, expected: Int) {
        #expect(temperatureScore(temperatureChange3h: change) == expected)
    }
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL（3 つの関数が未定義）

**Step 3: 実装する**

`Scoring.swift` に追記:

```swift
/// 湿度スコア（最大 3pt）。高湿度と気圧低下が重なる場合にボーナスを加える。
/// ラベルを `pressureChange3h` としているのは、気温の 3 時間変化との取り違えを防ぐため。
/// 型もラベルも同じだと Task 8 で両者が同一スコープに入った際、誤りが型検査を素通りする。
func humidityScore(humidity: Double, pressureChange3h: Double) -> Int {
    var score = 0
    if humidity >= 85 { score += 2 }
    else if humidity >= 75 { score += 1 }
    if humidity >= 75 && pressureChange3h <= -4 { score += 1 }
    return score
}

/// 降水スコア（最大 2pt）。
func precipitationScore(chance: Double, amount: Double) -> Int {
    var score = 0
    if chance >= 80 { score += 2 }
    else if chance >= 60 { score += 1 }
    if amount > 2 && score < 2 { score += 1 }
    return score
}

/// 気温変動スコア（最大 2pt）。3 時間以内の急変を評価する。
func temperatureScore(temperatureChange3h: Double) -> Int {
    let change = abs(temperatureChange3h)
    if change >= 8 { return 2 }
    if change >= 5 { return 1 }
    return 0
}
```

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 湿度・降水・気温スコアを実装"
```

---

### Task 6: 複合スコアとリスクレベル変換

移植元: `src/index.ts:181-189`。

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/CompositeRisk.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/CompositeRiskTests.swift`

**Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import RiskEngine

@Suite("複合リスク")
struct CompositeRiskTests {

    @Test("スコアからリスクレベルへの変換", arguments: [
        (0, RiskLevel.calm), (1, .slight), (3, .slight),
        (4, .caution), (6, .caution), (7, .danger), (13, .danger)
    ])
    func levelConversion(score: Int, expected: RiskLevel) {
        #expect(riskLevel(forScore: score) == expected)
    }

    @Test("複合スコアは各要因の和になる")
    func sumsFactors() {
        let result = compositeRisk(
            pressureChanges: PressureChanges(oneHour: -4, threeHour: -8, sixHour: -10),
            pressurePercentile: 0.05,
            humidity: 90, precipitationChance: 90, precipitationAmount: 5,
            temperatureChange3h: -8
        )
        #expect(result.factors.pressureChange == 8)
        #expect(result.factors.pressureBaseline == 3)
        #expect(result.factors.pressure == 11)      // 分割前と同じ値になること
        #expect(result.factors.humidity == 3)
        #expect(result.factors.precipitation == 2)
        #expect(result.factors.temperature == 2)
        #expect(result.score == 18)                 // 設計上の最大値
        #expect(result.level == .danger)
    }

    @Test("穏やかな条件では安心レベルになる")
    func calmConditions() {
        let result = compositeRisk(
            pressureChanges: PressureChanges(oneHour: 0.5, threeHour: 1, sixHour: 1.5),
            pressurePercentile: 0.6,
            humidity: 50, precipitationChance: 10, precipitationAmount: 0,
            temperatureChange3h: 1
        )
        #expect(result.score == 0)
        #expect(result.level == .calm)
    }
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL（`cannot find 'compositeRisk' in scope`）

**Step 3: 実装する**

`CompositeRisk.swift`:

```swift
/// リスク判定の結果。`HourlyRisk` 経由でアプリ層へ公開される。
public struct RiskAssessment: Sendable, Equatable {
    public let level: RiskLevel
    public let score: Int
    public let factors: RiskFactors
}

/// スコアからリスクレベルへの変換。閾値は src/index.ts の computeCompositeRisk に一致させている。
func riskLevel(forScore score: Int) -> RiskLevel {
    if score >= 7 { return .danger }
    if score >= 4 { return .caution }
    if score >= 1 { return .slight }
    return .calm
}

/// 複合リスクスコア（最大 18pt）。
/// 気圧 11pt ＋ 湿度 3pt ＋ 降水 2pt ＋ 気温変動 2pt。
func compositeRisk(
    pressureChanges: PressureChanges,
    pressurePercentile: Double,
    humidity: Double, precipitationChance: Double, precipitationAmount: Double,
    temperatureChange3h: Double
) -> RiskAssessment {
    let factors = RiskFactors(
        pressureChange: pressureChangeScore(pressureChanges),
        pressureBaseline: absolutePressureScore(percentile: pressurePercentile),
        humidity: humidityScore(humidity: humidity, pressureChange3h: pressureChanges.threeHour),
        precipitation: precipitationScore(chance: precipitationChance, amount: precipitationAmount),
        temperature: temperatureScore(temperatureChange3h: temperatureChange3h)
    )
    return RiskAssessment(level: riskLevel(forScore: factors.total),
                          score: factors.total,
                          factors: factors)
}
```

`RiskAssessment` は public だが memberwise init は internal のままでよい（エンジン内部でのみ生成する）。

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 複合スコアとレベル変換を実装"
```

---

### Task 7: 時系列からの変化量算出

移植元: `src/index.ts:225` 以降の `analyzeRisk` 内の差分計算部分。

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/PressureChange.swift`
- Modify: `ios/ZutsuuKit/Tests/RiskEngineTests/TestHelpers.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/PressureChangeTests.swift`

**Step 1: 失敗するテストを書く**

配列の先頭付近では過去のデータが足りない。ここの扱いを明示的にテストする。

`TestHelpers.swift` に追記:

```swift
func makeSeries(pressures: [Double], temperatures: [Double]? = nil) -> [WeatherPoint] {
    let base = Date(timeIntervalSince1970: 0)
    return pressures.enumerated().map { index, pressure in
        WeatherPoint(date: base.addingTimeInterval(TimeInterval(index) * 3600),
                     pressure: pressure,
                     temperature: temperatures?[index] ?? 20,
                     humidity: 50, precipitationChance: 0, precipitationAmount: 0)
    }
}
```

`PressureChangeTests.swift`:

```swift
import Testing
import Foundation
@testable import RiskEngine

@Suite("時系列の変化量")
struct PressureChangeTests {

    @Test("N時間前との差を取る")
    func overHours() {
        let series = makeSeries(pressures: [1010, 1008, 1006, 1004, 1002, 1000, 998])
        #expect(pressureChange(series, at: 6, hoursAgo: 1) == -2)
        #expect(pressureChange(series, at: 6, hoursAgo: 3) == -6)
        #expect(pressureChange(series, at: 6, hoursAgo: 6) == -12)
    }

    @Test("過去データが足りない場合は0を返す")
    func insufficientHistory() {
        let series = makeSeries(pressures: [1010, 1008, 1006])
        #expect(pressureChange(series, at: 0, hoursAgo: 1) == 0)
        #expect(pressureChange(series, at: 2, hoursAgo: 6) == 0)
    }

    @Test("気温の変化量も同じ規則で取れる")
    func temperature() {
        let series = makeSeries(pressures: [1013, 1013, 1013, 1013],
                                temperatures: [10, 13, 16, 19])
        #expect(temperatureChange(series, at: 3, hoursAgo: 3) == 9)
    }

    @Test("3つの時間窓をまとめて取れる")
    func aggregate() {
        let series = makeSeries(pressures: [1010, 1008, 1006, 1004, 1002, 1000, 998])
        let changes = pressureChanges(series, at: 6)
        #expect(changes.oneHour == -2)
        #expect(changes.threeHour == -6)
        #expect(changes.sixHour == -12)
    }
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL（`cannot find 'pressureChange' in scope`）

**Step 3: 実装する**

`PressureChange.swift`:

```swift
import Foundation

/// index から hoursAgo 時間前との気圧差。
/// 系列が 1 時間刻みであることを前提とする。
/// 過去データが足りない場合は 0（＝変化なし扱い）を返す。
/// これは安全側の挙動：データ不足を「急変」と誤判定して外れ通知を出すより、
/// 発火しないほうが信頼を損なわない。
func pressureChange(_ series: [WeatherPoint], at index: Int, hoursAgo: Int) -> Double {
    change(series, at: index, hoursAgo: hoursAgo) { $0.pressure }
}

func temperatureChange(_ series: [WeatherPoint], at index: Int, hoursAgo: Int) -> Double {
    change(series, at: index, hoursAgo: hoursAgo) { $0.temperature }
}

/// スコアリングが必要とする 3 つの時間窓をまとめて取る。
func pressureChanges(_ series: [WeatherPoint], at index: Int) -> PressureChanges {
    PressureChanges(oneHour: pressureChange(series, at: index, hoursAgo: 1),
                    threeHour: pressureChange(series, at: index, hoursAgo: 3),
                    sixHour: pressureChange(series, at: index, hoursAgo: 6))
}

private func change(_ series: [WeatherPoint], at index: Int, hoursAgo: Int,
                    value: (WeatherPoint) -> Double) -> Double {
    let past = index - hoursAgo
    guard past >= 0, index < series.count else { return 0 }
    return value(series[index]) - value(series[past])
}
```

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 時系列からの変化量算出を実装"
```

---

### Task 8: 時系列全体のリスク解析

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/RiskAnalyzer.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/RiskAnalyzerTests.swift`

**Step 1: 失敗するテストを書く**

`RiskAnalyzer` は public API なので、**素の `import RiskEngine`** でテストする。
これにより `public` の付け忘れを検出できる。

```swift
import Testing
import Foundation
import RiskEngine

@Suite("時系列リスク解析")
struct RiskAnalyzerTests {

    @Test("各時刻のリスクが算出される")
    func onePerPoint() {
        let series = makeSeries(pressures: Array(repeating: 1013, count: 24))
        let analyzer = RiskAnalyzer(climatology: StubClimatology(value: 0.5),
                                    latitude: 35.7, longitude: 139.6)
        let result = analyzer.analyze(series)
        #expect(result.count == 24)
        #expect(result.allSatisfy { $0.assessment.level == .calm })
    }

    @Test("気圧が急降下する区間でリスクが上がる")
    func detectsPressureDrop() {
        var pressures = [Double](repeating: 1013, count: 12)
        pressures += stride(from: 1011.0, through: 995.0, by: -2.0)
        let analyzer = RiskAnalyzer(climatology: StubClimatology(value: 0.5),
                                    latitude: 35.7, longitude: 139.6)
        let result = analyzer.analyze(makeSeries(pressures: pressures))
        #expect(result.last!.assessment.level >= .caution)
    }

    @Test("空の系列を渡しても落ちない")
    func emptySeries() {
        let analyzer = RiskAnalyzer(climatology: StubClimatology(value: 0.5),
                                    latitude: 0, longitude: 0)
        #expect(analyzer.analyze([]).isEmpty)
    }
}
```

`makeSeries` は `TestHelpers.swift` にある。同一テストモジュール内なので参照できる。

**`StubClimatology` を引数記録型に拡張すること。** 現在の実装は入力を捨てて定数を返すため、
`RiskAnalyzer` が `latitude` / `longitude` / `month` を正しく引き渡しているかを検証できない。
特に `calendar.component(.month, from: point.date)` の取り違えが素通りする。
最後に渡された引数を記録するか、クロージャを受け取る形にして、
「1月のデータには month=1 が渡る」ことを検証するテストを追加する。

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL（`cannot find 'RiskAnalyzer' in scope`）

**Step 3: 実装する**

`RiskAnalyzer.swift`:

```swift
import Foundation

public struct HourlyRisk: Sendable, Equatable {
    public let point: WeatherPoint
    public let assessment: RiskAssessment
    public let pressureChanges: PressureChanges
}

public struct RiskAnalyzer: Sendable {
    private let climatology: any PressureClimatology
    private let latitude: Double
    private let longitude: Double
    private let calendar: Calendar

    public init(climatology: any PressureClimatology,
                latitude: Double, longitude: Double,
                calendar: Calendar = .current) {
        self.climatology = climatology
        self.latitude = latitude
        self.longitude = longitude
        self.calendar = calendar
    }

    public func analyze(_ series: [WeatherPoint]) -> [HourlyRisk] {
        series.indices.map { index in
            let point = series[index]
            let changes = pressureChanges(series, at: index)
            let month = calendar.component(.month, from: point.date)

            let assessment = compositeRisk(
                pressureChanges: changes,
                pressurePercentile: climatology.percentile(
                    pressure: point.pressure,
                    latitude: latitude, longitude: longitude, month: month),
                humidity: point.humidity,
                precipitationChance: point.precipitationChance,
                precipitationAmount: point.precipitationAmount,
                temperatureChange3h: temperatureChange(series, at: index, hoursAgo: 3)
            )

            return HourlyRisk(point: point, assessment: assessment, pressureChanges: changes)
        }
    }
}
```

`HourlyRisk` の memberwise init は internal のままでよい（エンジン内部でのみ生成する）。
ただし素の import でテストするため、**プロパティと型自体は public が必須**。

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 時系列リスク解析を実装"
```

---

### Task 9: 寒暖差検知

移植元: `detectTemperatureSwing()`。前日比の最高気温差が 5℃ 以上で注意報。

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/TemperatureSwing.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/TemperatureSwingTests.swift`

**Step 1: 失敗するテストを書く**

```swift
import Testing
import Foundation
@testable import RiskEngine

@Test("前日比5℃以上でアラート")
func swingAlertFires() {
    let swing = TemperatureSwing(todayMax: 25, yesterdayMax: 19)
    #expect(swing.difference == 6)
    #expect(swing.hasAlert)
}

@Test("5℃ちょうどでアラート、4.9℃では出ない")
func swingBoundary() {
    #expect(TemperatureSwing(todayMax: 25, yesterdayMax: 20).hasAlert)
    #expect(!TemperatureSwing(todayMax: 24.9, yesterdayMax: 20).hasAlert)
}

@Test("急に冷え込む場合もアラートになる")
func swingHandlesDrop() {
    let swing = TemperatureSwing(todayMax: 15, yesterdayMax: 23)
    #expect(swing.difference == -8)
    #expect(swing.hasAlert)
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL

**Step 3: 実装する**

`TemperatureSwing.swift`:

```swift
public struct TemperatureSwing: Sendable, Equatable {
    public static let threshold: Double = 5

    public let todayMax: Double
    public let yesterdayMax: Double

    public init(todayMax: Double, yesterdayMax: Double) {
        self.todayMax = todayMax
        self.yesterdayMax = yesterdayMax
    }

    /// 前日比の差。正なら暖かくなる、負なら冷え込む。
    public var difference: Double { todayMax - yesterdayMax }

    /// 上昇・下降のどちらでも自律神経に負荷がかかるため絶対値で判定する。
    public var hasAlert: Bool { abs(difference) >= Self.threshold }
}
```

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 寒暖差検知を実装"
```

---

### Task 10: 通知予約時刻の算出

設計書 §4 の中核。**アプリ層はここが返した時刻をそのまま `UNNotificationRequest` に渡すだけ**にする。
判断ロジックを純粋関数に閉じ込めることで、通知の挙動をシミュレータ無しで検証できる。

**Files:**
- Create: `ios/ZutsuuKit/Sources/RiskEngine/AlertScheduler.swift`
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/AlertSchedulerTests.swift`

**Step 1: 失敗するテストを書く**

```swift
import Testing
import Foundation
@testable import RiskEngine

@Test("リスクが注意以上に上がる時刻の90分前に予約される")
func schedulesBeforeRiskRise() {
    let risks = makeRiskCurve(levels: [.calm, .calm, .calm, .caution, .caution])
    let alerts = AlertScheduler().schedule(risks, quietHours: nil)
    #expect(alerts.count == 1)
    // 3番目（3時間後）に上がるので、その90分前
    let expected = risks[3].point.date.addingTimeInterval(-90 * 60)
    #expect(alerts[0].fireDate == expected)
    #expect(alerts[0].targetLevel == .caution)
}

@Test("リスクが上がり続けても1回しか予約しない")
func schedulesOncePerRise() {
    let risks = makeRiskCurve(levels: [.calm, .caution, .caution, .danger, .danger])
    let alerts = AlertScheduler().schedule(risks, quietHours: nil)
    // caution への上昇と danger への上昇でそれぞれ1回
    #expect(alerts.count == 2)
}

@Test("最初から高リスクの場合は予約しない")
func noAlertWhenAlreadyHigh() {
    let risks = makeRiskCurve(levels: [.danger, .danger, .danger])
    #expect(AlertScheduler().schedule(risks, quietHours: nil).isEmpty)
}

@Test("やや注意までしか上がらない場合は予約しない")
func noAlertBelowThreshold() {
    let risks = makeRiskCurve(levels: [.calm, .slight, .slight])
    #expect(AlertScheduler().schedule(risks, quietHours: nil).isEmpty)
}

@Test("静穏時間に入る通知は予約されない")
func skipsQuietHours() {
    let risks = makeRiskCurve(levels: [.calm, .calm, .caution], startHour: 23)
    let quiet = QuietHours(start: 22, end: 8.5)
    #expect(AlertScheduler().schedule(risks, quietHours: quiet).isEmpty)
}
```

**Step 2: 失敗を確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: FAIL

**Step 3: 実装する**

`AlertScheduler.swift`:

```swift
import Foundation

public struct QuietHours: Sendable, Equatable {
    public let start: Double   // 22.0 = 22:00
    public let end: Double     // 8.5 = 08:30

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
    }
}

public struct ScheduledAlert: Sendable, Equatable {
    public let fireDate: Date
    public let targetDate: Date
    public let targetLevel: RiskLevel
}

public struct AlertScheduler: Sendable {
    /// 症状発現の何分前に通知するか。設計書 §4 の「1〜2時間前」の中央値。
    public static let leadTime: TimeInterval = 90 * 60

    /// これ以上のレベルへ上がる場合のみ通知する。
    public static let threshold: RiskLevel = .caution

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// リスク曲線から通知予約のリストを作る。
    /// 「レベルが上がった瞬間」だけを拾う。高いレベルが続く間は再通知しない。
    public func schedule(_ risks: [HourlyRisk], quietHours: QuietHours?) -> [ScheduledAlert] {
        guard risks.count > 1 else { return [] }

        var alerts: [ScheduledAlert] = []
        for index in 1..<risks.count {
            let previous = risks[index - 1].assessment.level
            let current = risks[index].assessment.level

            guard current > previous, current >= Self.threshold else { continue }

            let targetDate = risks[index].point.date
            let fireDate = targetDate.addingTimeInterval(-Self.leadTime)

            if let quietHours, quietHours.contains(fireDate, calendar: calendar) { continue }

            alerts.append(ScheduledAlert(fireDate: fireDate,
                                         targetDate: targetDate,
                                         targetLevel: current))
        }
        return alerts
    }
}
```

**Step 4: テストが通ることを確認**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS

**Step 5: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 通知予約時刻の算出を実装"
```

---

### Task 11: 既存 TS 実装との一致を検証する回帰テスト

移植の正しさを担保する。既存 `src/index.ts` に同じ入力を与えた結果と突き合わせる。

**Files:**
- Create: `ios/ZutsuuKit/Tests/RiskEngineTests/ParityTests.swift`

**Step 1: TS 側の期待値を得る**

`src/index.ts` の `computeCompositeRisk` を代表的な入力で実行し、出力を記録する。
絶対気圧スコアはパーセンタイル方式へ変更したため、**TS 側の絶対気圧項を 0 にした条件で比較する**。

```bash
npx tsx -e '
const cases = [
  [-4, -8, -10, 1013, 90, 90, 5, -8],
  [-2, -4, -6, 1013, 75, 60, 0, -5],
  [0, 0, 0, 1013, 50, 0, 0, 0],
  [3, 6, 10, 1013, 60, 30, 1, 6],
];
for (const c of cases) console.log(JSON.stringify(c));
'
```

**Step 2: 期待値を Swift テストに書く**

```swift
import Testing
@testable import RiskEngine

/// src/index.ts の computeCompositeRisk と同じ結果になることを確認する。
/// 絶対気圧項はパーセンタイル方式へ変更したため percentile: 0.5（=0pt）で比較する。
@Test("既存TS実装と同じスコアになる", arguments: [
    (change1h: -4.0, change3h: -8.0, change6h: -10.0, humidity: 90.0,
     chance: 90.0, amount: 5.0, tempChange: -8.0, expectedScore: 15),
    (change1h: -2.0, change3h: -4.0, change6h: -6.0, humidity: 75.0,
     chance: 60.0, amount: 0.0, tempChange: -5.0, expectedScore: 7),
    (change1h: 0.0, change3h: 0.0, change6h: 0.0, humidity: 50.0,
     chance: 0.0, amount: 0.0, tempChange: 0.0, expectedScore: 0),
])
func parityWithTypeScript(change1h: Double, change3h: Double, change6h: Double,
                          humidity: Double, chance: Double, amount: Double,
                          tempChange: Double, expectedScore: Int) {
    let result = compositeRisk(
        pressureChanges: PressureChanges(oneHour: change1h, threeHour: change3h, sixHour: change6h),
        pressurePercentile: 0.5,
        humidity: humidity, precipitationChance: chance, precipitationAmount: amount,
        temperatureChange3h: tempChange
    )
    #expect(result.score == expectedScore)
}
```

**注意:** 上記の `expectedScore` は手計算値。Step 1 で実際に TS を実行し、
食い違ったら**TS 側を正**として Swift を直す。移植のバグを見つけるのがこのタスクの目的。

**Step 3: テストを実行**

Run: `cd ios/ZutsuuKit && swift test`
Expected: PASS（不一致があれば Swift 側を修正）

**Step 4: コミット**

```bash
git add ios/ZutsuuKit && git commit -m "RiskEngine: 既存TS実装との回帰テストを追加"
```

---

### Task 12: 仕上げ

**Step 1: 全テストを実行**

Run: `cd ios/ZutsuuKit && swift test 2>&1 | tail -20`
Expected: 全 PASS、失敗 0 件

**Step 2: 警告なしでビルドできることを確認**

Run: `cd ios/ZutsuuKit && swift build -Xswiftc -warnings-as-errors`
Expected: 成功

**Step 3: リスク段階の記述を修正**

`SPEC.md` の「リスクレベル変換」表と `CLAUDE.md` の同等の記述がどちらも 5 段階になっているが、
実装は 4 段階。両方を実装に合わせて修正し、設計書 §2 と整合させる。

**Step 4: 繰り越した Minor 指摘を処理する**

Batch A のレビューで Task 12 へ繰り越した項目。

- **M7:** `Codable` / `Hashable` の準拠方針を決める。設計書 §3 の ForecastStore（予報キャッシュ）と
  LogStore が SwiftData を使うため、型が少ない今のうちに決めておく
- **M8:** `Package.swift` に `swiftLanguageModes: [.v6]` を明示する。
  tools-version 6.2 の既定で現在は v6 だが、明示すれば tools-version 変更時の暗黙の退行を防げる
- **M9:** `.github/workflows/` に Swift パッケージ用のジョブを追加する。
  現状は Node の LINE 版ジョブ 2 本しかなく、完了条件の `swift test` がローカル限定の保証になっている。
  `macos-latest` で `swift test` と `swift build -Xswiftc -warnings-as-errors` を回す
- **M10:** 解決済み。watchOS プラットフォームコンポーネントのインストール後、
  `xcodebuild build -scheme ZutsuuKit -destination 'generic/platform=watchOS'` の成功を実測で確認した。
  スキーム名は `RiskEngine` ではなく `ZutsuuKit`（パッケージ名）である点に注意

**Step 5: コミット**

```bash
git add -A && git commit -m "RiskEngine: 仕上げ（ドキュメント整合・CI・繰り越し指摘）"
```

---

## 完了条件

- `swift test` が全件 PASS
- `swift build -Xswiftc -warnings-as-errors` が成功
- `RiskEngine` が WeatherKit / UIKit / SwiftUI のいずれにも依存していない
  （確認: `grep -rE "import (WeatherKit|UIKit|SwiftUI)" ios/ZutsuuKit/Sources` が空）
- 設計書 §5 の 4 つのグローバル対応のうち、5.1（パーセンタイル）と 5.2（タイムゾーン、`Calendar` 注入）が実装済み
