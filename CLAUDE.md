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
3. **isMorningBriefingTime()** - 朝の予報時間帯（8:30〜9:30）判定
4. **fetchWithRetry()** - API取得（3回リトライ）
5. **fetchWeatherForecast()** - Open-Meteo APIから気象予報取得（気圧・気温・湿度・降水、昨日〜3日後）
6. **computeCompositeRisk()** - 気圧・湿度・降水・気温変動の複合スコアでリスクレベルを算出
7. **analyzeRisk()** - 今後24時間の毎時リスクを分析
8. **detectTemperatureSwing()** - 前日比の最高気温差（5℃以上）を検知
9. **buildAdvice()** - リスク要因に応じた具体的アドバイスを生成
10. **formatMorningBriefing()** - 朝の総合予報（湿度・寒暖差含む）
11. **formatAlertMessage()** - 緊急アラート（要因内訳・具体的アドバイス含む）
12. **shouldSendAlert()** - 1〜2時間後にリスク3以上になる場合アラート発火
13. **sendLineMessage()** - LINE Messaging API経由で通知

## 複合リスクスコア

気圧（最大11pt）＋湿度（最大3pt）＋降水（最大2pt）＋気温変動（最大2pt）= 最大18pt

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
