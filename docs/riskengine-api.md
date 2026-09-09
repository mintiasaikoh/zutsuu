# RiskEngine API 仕様

**この文書が RiskEngine の正典。** 実装と食い違う記述を見つけた場合、本文書か実装のどちらかが誤りであり、放置してはならない。

- `docs/plans/2026-08-30-riskengine-implementation.md` は**実装計画の履歴記録**であり、本文よりタスク本文のコード片が古い。API の参照元にしてはならない。
- `docs/plans/2026-08-30-global-ios-app-design.md` は**製品・アーキテクチャの設計判断**とその理由。「なぜそうなっているか」はそちらにある。
- `SPEC.md` / `CLAUDE.md` は**レガシーの TypeScript 版（LINE 通知）**の仕様。別システムである。

最終更新: 2026-08-31

---

## 1. パッケージ

```
ios/ZutsuuKit/
├── Package.swift
├── Sources/RiskEngine/        # 13 ファイル
├── Sources/KiabouUI/          # 7 ファイル + Resources/（3D 素材・背景画像）
├── Sources/PersonalRisk/      # 1 ファイル（依存: RiskEngine）
├── Sources/AppCore/           # 5 ファイル（依存: RiskEngine）
├── Tests/RiskEngineTests/     # 12 ファイル
├── Tests/KiabouUITests/       # 3 ファイル
├── Tests/PersonalRiskTests/   # 1 ファイル
└── Tests/AppCoreTests/        # 5 ファイル
```

`KiabouUI` は 1 タップ体調記録ときあぼう表示の UI ライブラリ（正典は `docs/kiabou-integration.md`）、`PersonalRisk` は体調記録から通知閾値を個人化する回帰モデル（正典は `docs/personalrisk-api.md`）、`AppCore` は WeatherKit 変換・通知文面・予約の温存判断などアプリ層の純粋ロジック（正典は `docs/appcore-api.md`）。いずれも本文書のスコープ外。RiskEngine は他のターゲットに依存しない。

| 項目 | 値 |
|---|---|
| tools-version | 6.2 |
| 言語モード | `swiftLanguageModes: [.v6]`（明示） |
| 対応プラットフォーム | iOS 18 / watchOS 11 / macOS 15 |
| 警告の扱い | `swiftSettings: [.treatAllWarnings(as: .error)]` |
| テストフレームワーク | Swift Testing（XCTest は不使用） |

`macOS(.v15)` を含めているのは `swift test` を Mac 上で直接回すため。シミュレータを起動せずに全ロジックを検証できることがこのパッケージの設計目的である。

**RiskEngine は WeatherKit / UIKit / SwiftUI を import しない。** アプリ層が WeatherKit のデータを `WeatherPoint` に変換して渡す。

### CI

`.github/workflows/ios.yml` が push / pull_request で以下を実行する。

- `swift build --build-tests -Xswiftc -warnings-as-errors`
  `--build-tests` が必須。これが無いとテストターゲットに警告検査が届かない（実測確認済み）
- `swift test` と `swift test -c release` の両方
  リリース構成でのみ落ちる差異が過去に発生している
- `xcodebuild build -scheme ZutsuuKit-Package -destination 'generic/platform=iOS'` および `watchOS`
  スキーム名は product 名ではなく自動生成の集約スキーム **`ZutsuuKit-Package`**。
  product が 1 つの間は `ZutsuuKit` だったが、複数化で変わった（Xcode の命名規則）

---

## 2. 公開 API

**公開型の memberwise init はすべて public。** SwiftUI プレビューとテストが合成データを組めるようにするため。

### 2.1 値型

#### `RiskLevel: Int, Sendable, Hashable, Comparable, CaseIterable`

| case | rawValue | 意味 |
|---|---|---|
| `.calm` | 1 | 安心 |
| `.slight` | 2 | やや注意 |
| `.caution` | 3 | 注意 |
| `.danger` | 4 | 危険 |

比較は `rawValue` 順（宣言順ではない）。**rawValue は変更禁止** — TypeScript 実装との移植契約であり、将来の永続化キーでもある。

#### `RiskFactors: Sendable, Hashable`

| プロパティ | 型 | 範囲 |
|---|---|---|
| `pressureChange` | `Int` | 0〜8 |
| `pressureBaseline` | `Int` | 0〜3 |
| `humidity` | `Int` | 0〜3 |
| `precipitation` | `Int` | 0〜2 |
| `temperature` | `Int` | 0〜2 |
| `pressure` | `Int`（computed） | `pressureChange + pressureBaseline` |
| `total` | `Int`（computed） | 5 要因の和、0〜18 |

気圧を 2 フィールドに分けているのは、UI が「急降下中」と「この土地としては低い」を区別できるようにするため。合算後は分離できない。

#### `PressureChanges: Sendable, Hashable`

`oneHour` / `threeHour` / `sixHour`（すべて `Double`、hPa）。

**前方差分。** 「その時刻から N 時間後までに何 hPa 変化するか」であって、過去との差ではない。負値は「これから下がる」を意味する。

#### `WeatherPoint: Sendable, Hashable`

気象データの中立表現。アプリ層が WeatherKit から変換する境界型。

| プロパティ | 単位 |
|---|---|
| `date` | — |
| `pressure` | hPa（海面気圧） |
| `temperature` | ℃ |
| `humidity` | **%（0〜100）** |
| `precipitationChance` | **%（0〜100）** |
| `precipitationAmount` | mm |

**⚠️ 単位の罠。** WeatherKit は `humidity` と `precipitationChance` を **0...1 の比率**で提供する。アダプタで 100 倍しないと、湿度スコアと降水スコアが恒久的に 0 になり、例外も警告も出ない。範囲バリデーションは意図的に入れていない（誤って `0.85` が渡されても `0...100` の範囲内に収まるため検出できない）。**防御はアダプタ側のテストで行うこと。**

同様に WeatherKit の `pressure` / `temperature` / `precipitationAmount` は `Measurement` であり、`.value` は単位依存である。`.converted(to:)` を経ずに渡すと、例えば気圧を inHg（≒29.9）で渡した場合に気圧変化スコアが恒久的に 0 になる。これは 18pt 中 8pt にあたる最大の寄与項である。

#### `Coordinate: Sendable, Hashable`

`latitude` / `longitude`。緯度経度を束ねているのは入れ替えを型で表現不能にするため。本プロジェクトでは同型の隣接引数による取り違えが 3 度発生している。

#### `RiskAssessment: Sendable, Hashable`

`level: RiskLevel` / `score: Int` / `factors: RiskFactors`。

#### `TemperatureSwing: Sendable, Hashable`

| メンバ | 内容 |
|---|---|
| `static let threshold: Double` | `5`（℃） |
| `todayMax` / `yesterdayMax` | `Double` |
| `difference` | `todayMax - yesterdayMax`。**符号付き**（TS 実装は絶対値。文面の出し分けに使えるため符号を残した） |
| `hasAlert` | `abs(difference) >= threshold` |

**生成元はエンジンに存在しない。** TS の `detectTemperatureSwing()` は日境界の切り出しと各日の最高気温算出を含むが、Swift へ移植したのは比較部分のみ。生成は `AppCore` の `TemperatureSwingDetector`（`docs/appcore-api.md`）が担い、日境界は渡された `Calendar`、昨日のデータがなければ `nil`、取得元は WeatherKit の hourly を昨日 00:00 から取る、と決定済み（2026-09-09）。

#### `HourlyRisk: Sendable, Equatable, Identifiable`

`point: WeatherPoint` / `assessment: RiskAssessment` / `pressureChanges: PressureChanges` / `id: Date`（= `point.date`）。

**`Hashable` ではない。**

#### `QuietHours: Sendable, Equatable`

| メンバ | 内容 |
|---|---|
| `start` / `end` | `Double`。`22.0` = 22:00、`8.5` = 08:30。`end` ちょうどは静穏時間に**含まない** |
| `init(start:end:)` | **検証しない** |
| `isEnabled` | `start`/`end` が有限かつ `0..<24` でなければ debug で `assertionFailure`、release で `false`。有効なら `start != end`（幅ゼロ＝静穏時間なし） |
| `contains(_:calendar:)` | 時・分のみで判定。**秒は無視**。日跨ぎ（`start > end`）に対応 |

**`Hashable` ではない。** `contains` の `calendar` には既定値 `.current` があるため、アプリ層が意図せず端末カレンダーで呼べてしまう。

#### `AlertKind: Sendable, Equatable, Hashable`

| case | 意味 | `fireDate` と `targetDate` の関係 |
|---|---|---|
| `.advance` | 事前警告 | `fireDate < targetDate` |
| `.wakeUp` | 起床時通知 | **`fireDate >= targetDate`**（境界で同値） |

**これは通知が鳴る時刻の区別であって、身体に何が起きたかの主張ではない。** 睡眠中に気圧の影響を受けるかを調べたが、直接測定した研究は見つかっていない。文面は事実に留めること（「睡眠中に気圧が 8hPa 下がりました」は可、「睡眠中に影響を受けました」は不可）。

#### `ScheduledAlert: Sendable, Equatable`

| プロパティ | 内容 |
|---|---|
| `fireDate` | 発火時刻。必ず静穏時間の外、かつ `> now` |
| `targetDate` | エピソードの入口（閾値を最初に超えた時刻）。`.wakeUp` の集約時は束ねた中で最も早い入口 |
| `assessment` | エピソード中で最もスコアの高い時点の判定（同点なら最も早い） |
| `targetLevel` | `assessment.level` の導出（computed、格納しない） |
| `kind` | `AlertKind`。**既定値なし**（省略可にすると呼び出し側が `.advance` を暗黙に名乗れてしまうため） |

**`Hashable` ではない。**

**⚠️ `fireDate` と `targetDate` の前後関係は `kind` によって反転する。** 差を符号なしで扱う実装、あるいは `fireDate < targetDate` を仮定する実装は `.wakeUp` で壊れる。型では表現されていない（どちらも `Date`）。

アプリ層はこの `fireDate` をそのまま `UNNotificationRequest` のトリガに渡してよい。「発火すべきでない」理由はすべて `AlertScheduler` 側で落としてある。

### 2.2 プロトコル

#### `PressureClimatology: Sendable`

```swift
func percentile(pressure: Double, coordinate: Coordinate, month: Int) -> Double
```

その地点・その月の海面気圧分布における位置を 0.0〜1.0 で返す。0 に近いほど「その土地としては低い」。実装は Plan 6（NOAA 再解析ベースの静的テーブル）。**それまでアプリは `AppCore.NeutralClimatology`（常に 0.5）を使い、絶対気圧スコアは恒久的に 0 になる**（`docs/appcore-api.md`）。

戻り値が 0.0〜1.0 の外に出た場合と非有限値は、呼び出し側（`absolutePressureScore`）で吸収される。ただし NaN は debug で `assertionFailure` を起こす。

### 2.3 サービス型

#### `RiskAnalyzer: Sendable`

```swift
public static let lookaheadHours = 6
public init(climatology: any PressureClimatology, coordinate: Coordinate, calendar: Calendar = .current)
public func analyze(_ series: [WeatherPoint]) -> [HourlyRisk]
```

#### `AlertScheduler: Sendable`

```swift
public static let leadTime: TimeInterval = 90 * 60   // 5400 秒
public static let threshold: RiskLevel = .caution     // rawValue 3
public static let grace: TimeInterval = 60            // 秒
public init(calendar: Calendar = .current)
public func schedule(_ risks: [HourlyRisk], now: Date, quietHours: QuietHours?) -> [ScheduledAlert]
```

**引数順は `(_:now:quietHours:)`。**

`grace` が 0 でないのは、`UNTimeIntervalNotificationTrigger` が間隔を正でないと受け付けないため。

---

## 3. リスクスコアの完全な仕様

合計 0〜18pt。移植元は `src/index.ts` の `computeCompositeRisk`。絶対気圧の項のみ意図的に変更してある。

### 3.1 気圧変化（最大 8pt）

3 つの窓の**絶対値**で評価し、加算する。上昇・下降のどちらでも症状が出るため符号を見ない。

| 窓 | 条件 | 加点 |
|---|---|---|
| 1h | `>= 4` | +3 |
| | `>= 3` | +2 |
| | `>= 2` | +1 |
| 3h | `>= 8` | +3 |
| | `>= 6` | +2 |
| | `>= 4` | +1 |
| 6h | `>= 10` | +2 |
| | `>= 6` | +1 |

境界はすべて `>=`（閾値ちょうどで加点する）。

### 3.2 絶対気圧（最大 3pt）

固定閾値ではなく、その地点・その月の分布上の位置で評価する。

| パーセンタイル | 加点 |
|---|---|
| `< 0.10` | +3 |
| `< 0.25` | +2 |
| `< 0.40` | +1 |
| それ以外 | 0 |

境界はすべて `<`（片側）。0.10 ちょうどは 2、0.40 ちょうどは 0。

**なぜ固定閾値をやめたか。** TS 実装の `pressure <= 1005` は日本の温帯気候を前提とした値で、熱帯では年間を通して常時アラート、冬季の内陸高緯度では永久に無発火になる。分布上の相対位置で見ることでどの気候帯でも同じ意味になり、副次的に高標高地の問題（海面更正気圧と体感気圧の乖離）も解消する。

非有限値は debug で `assertionFailure`、release で 0 を返す。範囲外はクランプするが、**このクランプは現状すべての有限 `Double` に対して no-op** である（閾値がすべて片側 `<` のため）。有限値 400 万点の全数掃引で差分ゼロを確認済み。実際に効いているのは `isFinite` ガードのみ。クランプは、高気圧側の規則（例 `if clamped > 0.90`）を足した瞬間に効き始めるための保険として残してある。

### 3.3 湿度（最大 3pt）

- `humidity >= 85` → +2、`>= 75` → +1
- `humidity >= 75 && pressureChange3h <= -4` → さらに +1

第 2 引数のラベルが `pressureChange3h` であるのは、気温の 3 時間変化との取り違えを防ぐため。型もラベルも同じだと、取り違えが型検査を素通りする。

### 3.4 降水（最大 2pt）

- `chance >= 80` → +2、`>= 60` → +1
- `amount > 2 && score < 2` → +1

降水量の判定は `>`（2mm ちょうどは加点しない）。既に 2pt なら加点しない。確率 60〜79%（1pt）と 3mm の組み合わせで 2pt になる経路が存在する。

### 3.5 気温変動（最大 2pt）

3 時間先との差の絶対値で `>= 8` → 2、`>= 5` → 1。

### 3.6 レベル変換

| スコア | レベル |
|---|---|
| `>= 7` | `.danger` |
| `>= 4` | `.caution` |
| `>= 1` | `.slight` |
| それ以外 | `.calm` |

---

## 4. `RiskAnalyzer.analyze` の挙動

系列は**1 時間刻み・時刻昇順**であることを前提とする。検証はしない。

**末尾 `lookaheadHours`（= 6）点を返さない。** 前方差分の窓が系列外に出るため。72 点を渡すと 66 点が返る。6 点以下の系列は空配列、7 点なら 1 点。

**なぜ返さないのか。** 窓が欠けた点は気圧変化スコアが必然的に 0 になる。切り詰めないと、劣化した値が正常な値として下流に流れ、静かに「安心」と読まれる。点数が減ることは呼び出し側から見えるが、劣化した値は見えない。`hasCompleteLookahead` のようなフラグは消費側が無視できるため、返さないほうが強い。

各点について:

- 気圧変化は 1h / 3h / 6h の**前方差分**
- 月は**その点の日時**から、保持している `Calendar` のタイムゾーンで算出する。系列が月をまたげば点ごとに異なる平年分布を引く
- 気圧・湿度・降水確率・降水量はその点の値
- 気温変化は**3 時間先**との差（固定）

**24 時間への切り詰めは行わない**（TS 実装は先頭 24 時間のみを解析していた）。

---

## 5. `AlertScheduler.schedule` の完全なアルゴリズム

```
schedule = coalescingWakeUps( episodes(risks).compactMap { alert(for: $0) } )
```

### 5.1 エピソード検出

閾値（`.caution`）以上が連続する区間を 1 つのエピソードとする。

- 区間内で**最もスコアの高い**時点を代表判定とする。同点なら**最も早い**時点（更新条件が `>` のため）
- `targetDate` は区間の**入口**（最初に閾値を超えた時刻）
- **曲線の先頭（index 0）から既に閾値以上の区間は破棄する。** 上昇ではないため。条件は既に進行中であり、アプリ画面に表示されている
- 閾値未満に落ちてから再び上がれば別エピソードとして扱う

1 つの荒天で通知が連投されるのを防ぐための集約である。素朴に「レベルが上がった瞬間」を拾うと、`安心→やや注意→注意→危険` の緩やかな上昇で 2 件、閾値をまたいで振動する曲線ではさらに増える。

### 5.2 発火時刻の決定

エピソードごとに以下を順に適用する。**この順序が仕様である。**

| 順 | 規則 | 条件 | 結果 |
|---|---|---|---|
| 1 | 過去の破棄 | `targetDate > now` でない | **破棄**（等号も破棄） |
| 2 | リードタイム | — | `fireDate = targetDate - 90分`（絶対時刻演算） |
| 3 | 現在への繰り上げ | `fireDate <= now`（等号を含む） | `fireDate = now + 60秒` |
| 4 | **5a** リード消失の破棄 | `fireDate < targetDate` でない | **破棄** |
| 5 | 静穏時間の繰り下げ | 発火時刻が静穏時間内 | 静穏時間の明けへ移動。移動先が求まらなければ破棄 |
| 6 | **5b** 種別の決定 | `fireDate < targetDate` | `.advance`、そうでなければ **`.wakeUp`**（破棄しない） |

**5a と 5b の非対称が仕様の中心である。** 繰り上げ（規則 3）由来の追い越しは破棄し、繰り下げ（規則 5）由来の追い越しは起床時通知に変換する。前者は差し迫ったイベント、後者は就寝中に到来したイベントであり、扱いが異なる。

**規則 5 を規則 3 より後に置くこと。** 逆順だと、静穏時間がリードタイムより短い設定で破綻する。反例: 昼寝 13:00〜13:30、対象 14:00、現在 13:10。素の発火 12:30 は静穏外なので繰り下げが起きず、規則 3 で 13:11 に繰り上がって昼寝の最中に鳴る。

破棄経路は 3 つだけ（規則 1、規則 5a、規則 5 の移動先が求まらない場合）。

### 5.3 動作の確認例

静穏時間 22:00〜08:30、リード 90 分。

| onset | 発火 | 種別 |
|---|---|---|
| 23:00 | 21:30（静穏外なので繰り下げなし） | `.advance` |
| 09:00 | 08:30（繰り下げ後も対象に間に合う） | `.advance` |
| 03:00 | 08:30（繰り下げが対象を追い越す） | `.wakeUp` |
| 00:30 | 08:30（同上） | `.wakeUp` |
| 現在 12:59・対象 13:00・静穏なし | — | 破棄（規則 5a） |

30 分刻み 48 枠の掃引で破棄は 0。onset 00:00〜08:30 の 18 枠と 23:30 の計 19 枠（事前に知らせる術が物理的に存在しないケース）が `.wakeUp` になり、残り 29 枠は `.advance` になる（`everyOnsetSlotProducesAnAlert` が固定）。

### 5.4 起床時通知の集約

同じ `fireDate` を持つ `.wakeUp` を 1 件にまとめる。起きた瞬間に通知が複数並ぶのを防ぐため。

- 集約キーは **`Date` の厳密一致**（「同じ夜」という単位は実装に存在しない）
- `assessment` は束ねた中で最もスコアの高いもの、`targetDate` は最も早いもの
- したがって `assessment` と `targetDate` は**別の時点を指しうる**。判定は夜の最悪を、対象時刻は乱れの始まりを表す

**⚠️ `.advance` は集約しない。** 同一 `fireDate` の `.advance` が複数返りうる。例えば 09:00 と 10:00 に別々のエピソードがあると、どちらも繰り下げで発火時刻 08:30 になり、同時刻に 2 通の通知が返る。

### 5.5 夏時間

- リードタイムの計算は**絶対時刻演算**。夏時間の切替を跨いでも実時間 90 分になる。壁時計で 90 分にすると、春の飛ぶ 1 時間で存在しない時刻を作ってしまう
- 静穏時間の判定と繰り下げは**壁時計**。春に存在しない時刻が明けに指定された場合、直後の実在時刻へ送られる

---

## 6. 型では守られていない制約

以下はコードのコメントにのみ存在する。呼び出し側が守らなければ静かに壊れる。

1. **`RiskAnalyzer` と `AlertScheduler` は解析のたびに生成すること。** どちらも `Calendar` を値として保持するため init 時点のタイムゾーンが固定される。グローバルアプリでユーザーが移動した後も長寿命に持ち回すと、古いタイムゾーンで月と壁時計を判定する。型で防いでいないのは、テストの決定性のために注入可能である必要があるため
2. **`WeatherPoint` の単位**（§2.1 参照）
3. **`schedule` の入力は時刻昇順・等間隔**であること。検証しない。生成元は `RiskAnalyzer.analyze` のみを想定
4. **系列は 1 時間刻み。** `hoursAhead` は index のオフセットとして使われ、実際の時刻差は見ていない
5. **前方差分の向きを反転させないこと。** 後方差分にするとリスクのピークが降下の終わりに来て、90 分の先行が降下の最中に着地する
6. **TS の外挿フォールバック（`change1h * 3`）を復活させないこと。** 1 時間の変化から 6 時間の変化を作るのはデータの捏造にあたる
7. **`fireDate` と `targetDate` の前後関係は `kind` で反転する**（§2.1 参照）
8. **`RiskLevel.rawValue` は変更禁止**
9. **`schedule` は呼び出し時点で入口が過ぎたエピソードを返さない（規則 1）。** 就寝中の再スケジュール（バックグラウンド更新など）が onset の後に走ると、前回返した `.wakeUp` はもう返らない。アプリ層が予約済み通知を毎回無条件に置き換えると、起床時通知が静かに消える。未発火の予約をどう温存するかはアプリ層（Plan 2）が決めること

### 既知の限界

- `pressureChange(at: Int.max, hoursAhead: 6)` は境界チェックの前に加算がオーバーフローして SIGTRAP する。internal 関数であり呼び出し側は常に `series.indices` と 1/3/6 の定数を渡すため到達不能
- 負の `hoursAhead` は 0 ではなく後方差分を計算する（境界ガードであって符号検証ではない）
- 自由関数 `pressureChanges` と `HourlyRisk.pressureChanges` プロパティが同名。現状は曖昧さなし

---

## 7. テスト

| 構成 | 件数 |
|---|---|
| debug | 146（RiskEngine 97 + KiabouUI 13 + PersonalRisk 13 + AppCore 23） |
| release | 145（RiskEngine 96 + KiabouUI 13 + PersonalRisk 13 + AppCore 23） |

差は `#if DEBUG` の `assertionFailure` 検証（debug 3 件 / release 2 件）。

内部関数のテストは `@testable import`、公開 API のテストは素の `import RiskEngine` を使う。**素の import は `public` 付け忘れを検出する仕掛けであり、実際に 3 件のバグを検出している。** 新しい公開 API を足したら、素の import 側のテストから必ず 1 回は触ること。

`allSatisfy` を `analyze` の出力に使う場合は必ず件数の表明と併用すること。短い系列が返す空配列に対して真空成立する。

---

## 8. 未確定・未レビュー

現在なし。

2026-08-31 に `AlertKind` 導入・5a/5b 分割・起床時通知の集約（+285 行）の仕様適合レビューと品質レビュー（8 観点）を実施。挙動の仕様違反はゼロ。指摘は本文書の記述修正（§5.3 の掃引結果・規則番号の統一）、テストの件数表明の復元、§6.9 の追記として反映済み。`ScratchSweep.swift` は削除済み。
