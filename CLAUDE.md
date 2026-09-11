# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

気圧・湿度・気温・降水の複合リスクスコアで気象病を事前に通知するツール。Open-Meteo APIから気象予報を取得し、急変の約1〜2時間前にLINE Messaging APIで通知を送る。寒暖差アラート（前日比5℃以上）も搭載。

## コマンド

```bash
# ローカル実行（テストモード：LINE通知はコンソール出力）
npm run check

# LINE通知あり実行
LINE_CHANNEL_TOKEN="xxx" LINE_USER_ID="Uxxx" npm run check

# GitHub Actionsで手動実行
gh workflow run check.yml
```

## アーキテクチャ

単一ファイル構成（`src/index.ts`）:

1. **CONFIG** - 緯度経度、閾値、通知オフ時間の設定
2. **isQuietHours()** - 夜間（22:00〜8:30）判定
3. **isMorningBriefingTime()** - 朝の予報時間帯（8:30〜10:00）判定
4. **fetchWithRetry()** - API取得（3回リトライ）
5. **fetchWeatherForecast()** - Open-Meteo APIから気象予報取得（気圧・気温・湿度・降水、昨日〜3日後）
6. **computeCompositeRisk()** - 気圧・湿度・降水・気温変動の複合スコアでリスクレベルを算出
7. **fetchJmaPops()** - 気象庁APIから降水確率を取得し、Open-Meteoの値を上書き（日本国内限定）
8. **analyzeRisk()** - 今後24時間の毎時リスクを分析
9. **detectTemperatureSwing()** - 前日比の最高気温差（5℃以上）を検知
10. **buildAdvice()** - リスク要因に応じた具体的アドバイスを生成
11. **formatMorningBriefing()** - 朝の総合予報（湿度・寒暖差含む）
12. **formatAlertMessage()** - 緊急アラート（要因内訳・具体的アドバイス含む）
13. **shouldSendAlert()** - **1時間後**にリスク3以上になる場合アラート発火（現在リスク3以上なら発火しない）
14. **parseJmaTime() / fetchNowcastPrecip()** - 気象庁ナウキャスト（hrpns タイル）から降水強度を取得
15. **shouldSendRainAlert() / formatRainAlertMessage()** - 雨アラートの判定と整形
16. **buildRainForecast()** - 降水予報の文字列を組み立て
17. **sendLineMessage()** - LINE Messaging API経由で通知

## 複合リスクスコア

気圧（最大11pt）＋湿度（最大3pt）＋降水（最大2pt）＋気温変動（最大2pt）= 最大18pt

なお本ファイルの上記とSPEC.mdはレガシーのTypeScript版（LINE通知）を記述したもの。
iOSアプリ版のリスクエンジンは別実装であり、仕様は `docs/riskengine-api.md` を参照。

## iOS アプリの構成（2026-09-12 時点）

| 場所 | 中身 | 正典 |
|---|---|---|
| `ios/ZutsuuKit` | Swift Package: RiskEngine / PersonalRisk / KiabouUI / AppCore | `docs/riskengine-api.md`, `docs/personalrisk-api.md`, `docs/kiabou-integration.md`, `docs/appcore-api.md` |
| `ios/ZutsuuAds` | Swift Package: AdPolicy（純粋ロジック）/ ZutsuuAds（AdMob ラッパー）。ZutsuuKit に依存しない | `docs/plans/2026-09-12-admob-plan4.md` |
| `ios/ZutsuuApp` | iPhone アプリ（xcodegen。`project.yml` が正、`.xcodeproj` は生成物） | `docs/plans/2026-08-30-global-ios-app-design.md` |
| `ios/ZutsuuWatch`, `ios/ZutsuuWatchWidget` | Watch アプリとコンプリケーション | `docs/plans/2026-09-12-watchos-plan5.md` |
| `tools/climatology`, `tools/localization` | 平年値テーブルの生成、String Catalog の再抽出 | 各 README |

```bash
# パッケージのテスト
cd ios/ZutsuuKit && swift test
cd ios/ZutsuuAds && swift test --filter AdPolicyTests
# アプリのビルド（シミュレータ）
cd ios/ZutsuuApp && xcodegen generate && xcodebuild -scheme ZutsuuApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

シミュレータ検証の罠: AppStorage の仕込みは `simctl spawn … defaults write`（起動引数だと書き込みが効かない）、
アプリ終了直後の defaults 書き込みは書き戻しと競合する、Watch→iPhone の `transferUserInfo` は届かない（`sendMessage` は届く）、
署名なしビルドは entitlements が空（App Group・WeatherKit は実機で確認）、
iOS 26.3 シミュレータのスイッチ（Toggle）は短いタップを取りこぼす（システム設定アプリでも同じ。0.2 秒押すかドラッグで切り替わる。アプリの不具合ではない）。

| スコア | レベル |
|--------|--------|
| 7pt以上 | 4: 危険 |
| 4〜6pt | 3: 注意 |
| 1〜3pt | 2: やや注意 |
| 0pt | 1: 安心 |

## 環境変数

| 変数 | 説明 |
|------|------|
| LINE_CHANNEL_TOKEN | LINE Messaging APIのチャネルアクセストークン（長期） |
| LINE_USER_ID | 通知先のユーザーID（Uから始まる） |

## GitHub Secrets

- `LINE_CHANNEL_TOKEN`
- `LINE_USER_ID`
