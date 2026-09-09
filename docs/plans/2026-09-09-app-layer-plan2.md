# Plan 2: アプリ層の実装計画

> ⚠️ **この文書は実装計画であり、API の参照元ではない。** API の正典は各ターゲットの仕様書
> （`docs/riskengine-api.md` / `docs/personalrisk-api.md` / `docs/kiabou-integration.md` / `docs/appcore-api.md`）。
> 計画書に API 一覧を置くと必ず腐る（Plan 1 の教訓）。ここには「何を・どの順で・なぜ」だけを書く。

作成日: 2026-09-09

**Goal:** RiskEngine / PersonalRisk / KiabouUI を実機で動かす。WeatherKit から予報を取り、リスクを計算し、ローカル通知を予約し、体調を記録する。

**Architecture:** アプリ層を 2 層に分ける。

1. **`AppCore`（Swift Package ターゲット）** — WeatherKit → `WeatherPoint` の変換、寒暖差の生成、通知文面、予約の温存判断、平年値の暫定実装。UI と OS サービスに依存しない純粋ロジックで、`swift test` で検証する。エンジンと同じ規律（macOS で決定的にテスト）を保つ
2. **`ZutsuuApp`（Xcode プロジェクト、xcodegen 生成）** — SwiftUI 画面、WeatherKit 呼び出し、`UNUserNotificationCenter`、`BGAppRefreshTask`、SwiftData の保存。薄い配線層に留め、判断は AppCore に置く

**Tech Stack:** Swift 6.2 / SwiftPM / Swift Testing / xcodegen（`/opt/homebrew/bin/xcodegen` 導入済み）/ WeatherKit / UserNotifications / SwiftData

**参照:** 設計書 §3（アーキテクチャ）、§4（通知設計）、§6（パーソナライズ）、§9（コンプライアンス）。仕様書 `riskengine-api.md` §2.1（単位の罠・TemperatureSwing の未決事項）、§6.9（再スケジュールでの温存）

---

## 実施記録

| 部 | タスク | 状態 | コミット |
|---|---|---|---|
| A | Task 1–5（AppCore） | 完了 | `465b52c` |
| B | Task 6–9（ZutsuuApp） | 実装済み・シミュレータで起動確認済み。**WeatherKit の実データは未検証**（下記） | （本コミット） |

### Part B の検証状況（2026-09-09）

- xcodegen 生成・Swift 6 strict concurrency・警告エラー化でビルド成功。CI にもシミュレータビルドを追加
- iPhone 17 Pro シミュレータで起動、位置情報ダイアログ（説明文つき）→ 位置取得 → WeatherKit へのリクエスト送信までログで確認
- WeatherKit は `WDSJWTAuthenticatorServiceProxy.Errors error 0` で失敗。**Developer Portal で App ID `com.mintiasaikoh.zutsuu` に WeatherKit capability を有効化するまで実データは取れない**（Bundle ID を変える場合は `project.yml` の 1 箇所）
- SwiftData の初回起動ログに `default.store` の stat 失敗が出るが、ストア新規作成時の既知のノイズ
- 実機での確認事項: 位置情報ダイアログが毎回出ないこと（シミュレータでは `simctl privacy grant` 後も再表示された）、通知の実発火、バックグラウンド更新

---

## スコープ

**含む:** WeatherKit アダプタ、寒暖差の生成、通知の文面と識別子、予約済み通知の温存判断、平年値の暫定実装、Xcode アプリ本体（SwiftUI 骨格・予報取得・通知予約・バックグラウンド更新・体調記録の保存）

**含まない:** Plan 3 の画面作り込み（メイン画面の Tier 0 設計、深掘り画面）、Plan 4（AdMob）、Plan 5（watchOS）、Plan 6（平年値テーブル）、5 言語ローカライズ（文面は日本語で確定させてから String Catalog へ移す）

---

## Part A: AppCore（純粋ロジック）

### Task 1: WeatherKit アダプタ

WeatherKit の `HourWeather` を直接触ると単位の罠（`humidity` が 0...1、`pressure` が `Measurement`）をテストで守れない。
`HourWeather` と同じプロパティ名・型を持つプロトコル `HourlyWeatherSample` を切り、`HourWeather` は空の適合で通す。
変換ロジックはスタブで検証する。**hPa・℃・%・mm への変換を 1 箇所に閉じ込める**のが目的。

### Task 2: 寒暖差の生成

`riskengine-api.md` §2.1 が「アプリ層が決めること」とした 3 点を決める。

- 日境界: **呼び出し側が渡す `Calendar`**（既定値なし。`QuietHours.contains` の `.current` 既定を仕様書が問題視しているため同じ罠を作らない）
- 昨日のデータがない: **`nil` を返す**（寒暖差なしと区別する。アプリは表示を省く）
- 昨日の気温の取得元: WeatherKit の hourly は過去日付も返せる。アプリは**昨日 00:00 から 72 時間先まで**を 1 回で取得し、同じ系列を寒暖差とリスク解析の両方に渡す

### Task 3: 通知の文面と識別子

- 識別子は `kind` と `targetDate` から決定的に生成する。同じエピソードは再計算しても同じ識別子になり、予約の付け替えが起きない
- `.advance` と `.wakeUp` で文面を分ける（`fireDate` と `targetDate` の前後関係が反転するため）
- 文面は**事実のみ**（設計書 §4「睡眠中の影響を主張しない」、§9「予測・診断を避ける」）。「睡眠中に気圧が 8hPa 下がりました」は可、「影響を受けました」は不可
- 数値は入口時刻の `HourlyRisk` から取る（`ScheduledAlert` は点数しか持たない）

### Task 4: 予約済み通知の温存判断

`riskengine-api.md` §6.9 の帰結。再スケジュール時に予約済み通知を無条件に置き換えると、入口が過ぎた `.wakeUp` が消える。

- 同じ識別子が新しい予定にもある → 何もしない（付け替えない）
- 入口が過ぎた `.wakeUp` で発火が未来 → **温存**
- それ以外の予約済み → キャンセル（条件が消えた通知は外れ通知になる。設計書 §4「外れ通知は信頼を最も損なう」）
- 保留上限 64 件（設計書 §4）を超える分は発火の遅いものから落とす

### Task 5: 平年値の暫定実装

Plan 6 のテーブルができるまで、常にパーセンタイル 0.5 を返す `NeutralClimatology` を使う。絶対気圧スコア（最大 3pt）が恒久的に 0 になることを**仕様書に明記**し、黙って劣化させない。

---

## Part B: ZutsuuApp（Xcode プロジェクト）

### 前提条件（ユーザー側で必要）

| 項目 | 内容 |
|---|---|
| Apple Developer Program | WeatherKit は有料プログラムの登録が必要 |
| Bundle ID | App ID を Developer Portal に登録し、**WeatherKit capability を有効化**する。未登録だと WeatherKit が実行時にエラーを返す（ビルドは通る） |
| Team ID | xcodegen の `project.yml` に署名設定として記載 |
| 通知権限 | `UNUserNotificationCenter.requestAuthorization`。初回起動のオンボーディングで取得 |

### Task 6: プロジェクト骨格

`ios/ZutsuuApp/project.yml` から xcodegen で生成。ZutsuuKit をローカルパッケージ依存にする。Info.plist に WeatherKit の帰属表示（設計書 §9）、`BGTaskSchedulerPermittedIdentifiers`、`NSLocationWhenInUseUsageDescription`。

### Task 7: 予報パイプライン

位置取得 → WeatherKit（昨日 00:00〜+72h の hourly）→ `WeatherSeries.hourly` → `RiskAnalyzer.analyze`（解析のたびに生成。§6.1）→ 表示用と通知用に分岐。通知用は `PersonalRiskModel.schedulingLevel` で判定を差し替える（`personalrisk-api.md` §4）。

### Task 8: 通知予約

`AlertScheduler.schedule` → `NotificationReconciler.reconcile`（保留中の読み戻し込み）→ `UNUserNotificationCenter` へ add / remove。`BGAppRefreshTask` で同じパイプラインを回す。

### Task 9: 体調記録の保存

`KiabouCheckInView(onRecord:)` に SwiftData の保存を接続。記録と同時刻の `HourlyRisk.assessment.factors` を一緒に保存し、`SymptomObservation` に変換できる形にする（`kiabou-integration.md` §2.4）。再学習は記録成功のたびに実行。

---

## 完了条件

- Part A: `swift test` 両構成と CI の 4 ステップがすべて通る。仕様書 `docs/appcore-api.md` が実装と一致
- Part B: 実機またはシミュレータで、予報取得 → リスク表示 → 通知予約 → 体調記録 → 再学習が一巡する。WeatherKit の実データで絶対気圧以外の 4 要因が非ゼロになることを確認（単位の罠の実地検証）
