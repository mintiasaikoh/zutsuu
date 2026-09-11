# Plan 5: watchOS — コンプリケーション・通知・1 タップ記録

作成日: 2026-09-12。設計書 §7.2（線引き）と §10 v1.0（Watch: コンプリケーション、通知、1 タップ記録）の実装計画。
**実装は未着手。** 記録の転送方式など、下の「決定が要る点」をユーザーが決めてから着手する。

**参照:** 設計書 §7.2・§7.3・§10、`docs/kiabou-integration.md` §6（watchOS の 1 タップ記録は未実装）、
`docs/appcore-api.md` §3（アプリ層が守ること）、`docs/personalrisk-api.md` §4（記録と要因の突き合わせ）

## スコープ

| 含む | 含まない |
|---|---|
| 文字盤コンプリケーション（リスクレベルのみ） | 相関レポート・詳細予報・複数地点（iPhone のみ、§7.2） |
| 通知（iPhone の事前予約ローカル通知の**ミラー**。Watch 側で独自に予約しない） | HealthKit 読み取り（v1.1、§7.1） |
| 1 タップ記録（げんき／ふつう／つらい） | Watch 単体での予報取得（WeatherKit を Watch で叩かない） |
| 広告なし（watchOS に SDK が無い） | きあぼうの 3D 表示（RealityKit は Watch で使わない。値型のみ共有） |

## 決定が要る点（ユーザー）

1. **記録の転送方式**
   - **A. WatchConnectivity `transferUserInfo`（推奨）**: 到達保証あり、iPhone 未起動でも次回起動時に届く。
     受け側は `CheckInStore.save` が同じ `id` を重複保存しない契約（kiabou-integration.md §2.2）をそのまま使える
   - B. 共有の SwiftData ストア: Watch と iPhone は別デバイスなので**不可**（App Group は同一デバイス内のみ）
   - C. CloudKit 同期: iCloud 依存とプライバシー方針（§9「端末外に出さない」）に反するため不採用
2. **記録時の要因の突き合わせ**: Watch の記録に要因を付けるのは iPhone（受信時に `risk(at:)` で同時刻の要因を引く）。
   iPhone に届いたときに系列が古ければ `hasFactors = false` で保存する（既存の挙動と同じ）
3. **コンプリケーションの更新元**: iPhone の予報更新ごとに `updateApplicationContext` で「現在レベル + 24 時間の毎時レベル」を送り、
   Watch 側は App Group の UserDefaults に保存して WidgetKit のタイムラインを作る。Watch 単体で予報は取らない
4. **Watch の通知アクション**: ミラー通知に「つらい」「ふつう」「げんき」のアクションを付けるか（付けるなら iPhone 側で
   `UNNotificationCategory` を登録し、Watch 側で応答を記録として転送）。v1.0 では**付けない**ことを提案
   （通知からの記録は「調子が悪い時ほど記録する」バイアスを強める）

## タスク

### Task 1: 共有ペイロード（AppCore、純粋ロジック）
`WatchContext`（Codable, Sendable）: 現在の `RiskLevel`、24 時間の `(Date, RiskLevel)`、次の通知の見出し、累計記録日数。
`WatchCheckIn`（Codable）: `HealthCheckIn` と同じ `id` / `date` / `feeling.rawValue`。エンコード往復と後方互換のテスト。

### Task 2: iPhone 側の橋（ZutsuuApp）
`WatchSessionBridge`（`WCSessionDelegate`）。`ForecastPipeline.refresh` の末尾で `WatchContext` を送る。
受信した `WatchCheckIn` は `HealthCheckIn` に戻して `pipeline.record` と同じ経路（`store.save` → 再学習 → 再予約）で保存する。

### Task 3: Watch アプリ（新ターゲット `ZutsuuWatch`）
xcodegen に watchOS ターゲットを追加（Bundle ID `com.mintiasaikoh.zutsuu.watchkitapp`、ZutsuuKit の RiskEngine / KiabouUI 値型に依存）。
画面は 1 つ: 現在レベル（文字と色）+ 3 ボタン + 「記録したよ」。ボタンは iPhone と同じ語・同じ色（誘導しない）。
送信は `transferUserInfo`。未送信分は WatchConnectivity が保持する。

### Task 4: コンプリケーション（WidgetKit）
accessoryCircular / accessoryRectangular にレベル名だけ。タイムラインは `WatchContext` の 24 時間分。
iPhone から更新が来なければ最後の値を出し続け、6 時間以上古ければ「—」にする（古い予報を今と偽らない）。

### Task 5: 検証
- `swift test`（Task 1）、xcodebuild で iPhone + Watch のシミュレータビルド（CI にも追加）
- ペアリングしたシミュレータで: iPhone で予報更新 → Watch に現在レベルが出る → Watch で「つらい」→ iPhone のログに記録が出る
- iPhone を終了した状態で Watch から記録 → iPhone 起動後に届く（到達保証の確認）

## 完了条件
- Watch の記録が iPhone の記録ログに同じ `id` で 1 件だけ現れる（重複なし）
- コンプリケーションのレベルが iPhone の「いま」と一致する
- 設計書 §7.2 の線引き（Watch は Tier 0 相当の情報のみ）を破っていない

## 見積もり
Task 1〜2 で半日、Task 3〜4 で 1 日、検証で半日。実機（Apple Watch）での確認は別途ユーザーが必要。
