# AppCore API 仕様

**この文書が AppCore の正典。** 設計判断の理由は Plan 2 計画書（`docs/plans/2026-09-09-app-layer-plan2.md`）と設計書 §4、エンジンの仕様は `docs/riskengine-api.md` を参照。

最終更新: 2026-09-09

---

## 1. なにか

アプリ層のうち、UI と OS サービスに依存しない純粋ロジック。WeatherKit・UserNotifications・SwiftData を**呼ばない**（`WeatherKit` は型の適合のためだけに import する）。エンジンと同じく `swift test` で決定的に検証する。

```
ios/ZutsuuKit/Sources/AppCore/     # 5 ファイル（依存: RiskEngine）
ios/ZutsuuKit/Tests/AppCoreTests/  # 5 ファイル
```

| ファイル | 役割 |
|---|---|
| `WeatherKitAdapter.swift` | `HourWeather` → `WeatherPoint`（単位変換）、系列の整列 |
| `TemperatureSwingDetector.swift` | 系列から昨日・今日の最高気温を切り出し `TemperatureSwing` を作る |
| `AlertNotifications.swift` | `ScheduledAlert` → 通知の識別子と文面 |
| `NotificationReconciler.swift` | 保留中の予約と新しい予定の突き合わせ（温存・取消・追加） |
| `NeutralClimatology.swift` | テーブルが読めないときの退避用 `PressureClimatology`（常に 0.5） |
| `ReanalysisClimatology.swift` | 同梱の気圧平年値テーブル（Plan 6、2026-09-12） |
| `Resources/slp-climatology.bin` | テーブル本体（約 740KB）。`tools/climatology/build_slp_table.py` で生成 |

## 2. 公開 API

### `HourlyWeatherSample`（protocol）

WeatherKit の `HourWeather` と同じ名前・型のプロパティ。`HourWeather` は空の適合（`#if canImport(WeatherKit)`）。`humidity` と `precipitationChance` は **0...1 の比率**（WeatherKit の仕様のまま）。

### `WeatherPoint.init(_ sample: some HourlyWeatherSample)`

hPa / ℃ / % / mm へ揃える唯一の場所。`riskengine-api.md` §2.1 の単位の罠はここでテストにより防御する（inHg → hPa、°F → ℃、比率 → %、inch → mm）。

### `WeatherSeries.hourly(from:) -> [WeatherPoint]`

時刻昇順・同時刻の重複なし（最初の 1 件を残す）に整える。**等間隔は検証しない**（WeatherKit の hourly が毎時であることに依存）。

### `TemperatureSwingDetector.detect(in:now:calendar:) -> TemperatureSwing?`

`riskengine-api.md` §2.1 の未決 3 点の決定:

| 論点 | 決定 |
|---|---|
| 日境界 | 渡された `calendar` のタイムゾーンで `now` を含む暦日を「今日」、前日を「昨日」とする。**既定値なし** |
| 昨日のデータがない | `nil`。「寒暖差なし」とは区別する |
| 昨日の取得元 | アプリが WeatherKit の hourly を**昨日 00:00 から 72 時間先まで**まとめて取り、同じ系列をリスク解析にも渡す |

今日の最高気温は系列にある点だけから取る。朝の時点では予報値を含む。

### `AlertNotifications`

| メンバ | 内容 |
|---|---|
| `identifier(for:)` | `zutsuu.alert.{advance\|wakeup}.{targetDate の UNIX 秒}`。同じエピソードは再計算しても同じ識別子 |
| `content(for:risks:calendar:)` | `AlertNotificationContent`（identifier / fireDate / kind / targetDate / title / body）。数値は**入口時刻**の `HourlyRisk` から取る。入口が `risks` に無ければ数値なしの要因名 |

文面の規則:

- **事実のみ。** 「睡眠中に気圧が変化しました」「3時間で6hPa低下」は可。「影響を受けました」「予測」「診断」は不可（設計書 §4・§9）。テストで禁止語を固定
- `.advance` は「{H:mm} 頃から{レベル}」＋要因＋「対策するなら今のうちに。」
- `.wakeUp` は「睡眠中に気圧が変化しました」（気圧要因がなければ「睡眠中に{レベル}の条件になりました」）＋「{H:mm} 頃から{レベル}」＋要因
- 気圧の数値は 1h / 3h / 6h のうち変化量が最大の窓。1hPa 未満なら数値を出さない
- 時刻は `calendar` のタイムゾーン、`H:mm`（先頭ゼロなし）
- **日本語で確定させる段階。** ローカライズ（5 言語）は文面確定後に String Catalog へ移す

`RiskLevel.displayName`（安心 / やや注意 / 注意 / 危険）もここで定義する。暫定。

### `NotificationReconciler.reconcile(pending:scheduled:now:) -> ReconcilePlan`

`PendingAlert`（identifier / fireDate / kind / targetDate。アプリが `UNUserNotificationCenter` の保留分と `userInfo` から復元する）と `AlertScheduler.schedule` の結果を突き合わせる。

| 順 | 規則 | 結果 |
|---|---|---|
| 1 | 保留分の `fireDate <= now` | 対象外（温存も取消もしない） |
| 2 | 同じ識別子が新しい予定にもある | 温存（付け替えない） |
| 3 | `.wakeUp` かつ `targetDate <= now` | **温存**（`riskengine-api.md` §6.9） |
| 4 | それ以外の保留分 | 取消 |
| 5 | 温存 + 追加 > 64 | 追加を発火時刻順に切り詰める（`pendingLimit`） |

`ReconcilePlan.cancel` は取消する識別子、`.add` は追加する予定（発火時刻順）。

### `ReanalysisClimatology`（Plan 6、2026-09-12）

NCEP/NCAR Reanalysis 1 の日平均海面気圧 1991〜2020 年から作った、2.5° 格子 × 12 か月の **10・25・40 パーセンタイル値**（hPa × 10 の Int16）。
選定の経緯は `docs/research/2026-09-12-pressure-climatology.md`。

- `static func bundled() throws -> ReanalysisClimatology` — バンドルから読む。欠損・破損は `ClimatologyTableError`
- `init(data:) throws` — ヘッダ（`ZSLP`）とサイズ（16 + 12×73×144×3×2 = 756,880 byte）を検証する
- `percentile(pressure:coordinate:month:)` — 地点は格子 4 点の双一次補間、気圧は境界間の線形補間。
  **境界ちょうどで 0.10 / 0.25 / 0.40 を返す**（§3.2 の `<` 判定と噛み合う）。境界の外は同じ傾きで外挿し 0〜1 に収める。
  非有限の気圧は 0.5。月は 1〜12 に巻き戻し、経度は 360° で巻き、緯度は ±90 に収める
- 時別の値を日平均の分布に当てるため、裾は実際よりやや狭い（「低い」判定が出やすい側）。時別データでの作り直しは v1.1 以降の検討

アプリ層（`ForecastPipeline`）は起動時に一度 `bundled()` を試み、失敗したら `NeutralClimatology` に倒してログに残す。

### `NeutralClimatology`

常に 0.5 を返す退避用。これを使う間は絶対気圧スコア（最大 3pt）が 0 になる。2026-09-12 までは常用の暫定実装だった。

## 3. アプリ層（Part B）が守ること

1. **`WeatherPoint` は必ず `HourlyWeatherSample` 経由で作る。** `HourWeather` のプロパティから直接 `WeatherPoint.init(date:pressure:...)` を呼ぶ経路を作らない
2. 通知の `identifier` は `AlertNotifications.identifier(for:)` で作り、`kind` と `targetDate` を `userInfo` に入れて `PendingAlert` に復元できるようにする
3. 再スケジュールは必ず `NotificationReconciler` を通す。`removeAllPendingNotificationRequests()` を呼ばない
4. `RiskAnalyzer` / `AlertScheduler` は解析のたびに生成する（`riskengine-api.md` §6.1）

## 4. 未確定

- 文面のローカライズ方式（String Catalog を AppCore に置くか、アプリ側で組み立て直すか）
- `TemperatureSwing` の表示（通知には含めない。画面側の扱いは Plan 3）
