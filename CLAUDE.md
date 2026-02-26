# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

気圧変化による体調不良（気象病）を事前に通知するツール。Open-Meteo APIから気圧予報を取得し、急変の約1時間前にLINE Messaging APIで通知を送る。

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
3. **fetchWithRetry()** - API取得（3回リトライ）
4. **fetchPressureForecast()** - Open-Meteo APIから48時間分の気圧予報取得
5. **findUpcomingPressureChange()** - 1時間あたり±2hPa以上の急変を検知、1時間前なら通知対象
6. **formatMessage()** - 上昇/低下で異なるLINEメッセージ生成
7. **sendLineMessage()** - LINE Messaging API経由で通知

## 環境変数

| 変数 | 説明 |
|------|------|
| LINE_CHANNEL_TOKEN | LINE Messaging APIのチャネルアクセストークン（長期） |
| LINE_USER_ID | 通知先のユーザーID（Uから始まる） |

## GitHub Secrets

- `LINE_CHANNEL_TOKEN`
- `LINE_USER_ID`
