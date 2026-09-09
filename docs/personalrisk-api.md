# PersonalRisk API 仕様

**この文書が PersonalRisk の正典。** 設計判断の理由は設計書 §6.5、RiskEngine の仕様は `docs/riskengine-api.md`、体調記録の入力契約は `docs/kiabou-integration.md` を参照。

最終更新: 2026-09-09

---

## 1. なにか

体調記録から学習するロジスティック回帰で、**通知閾値だけ**を個人化するターゲット。

```
ios/ZutsuuKit/Sources/PersonalRisk/   # 1 ファイル（依存: RiskEngine のみ）
ios/ZutsuuKit/Tests/PersonalRiskTests/
```

- **画面のリスクレベル表示には使わない**（設計書 §6.5 の決定）。表示は汎用の `RiskAssessment` のまま
- Core ML 等の外部依存なし。学習は決定的で `swift test` で検証できる

## 2. 公開 API

### `SymptomObservation: Sendable, Hashable`

学習の 1 標本。`factors: RiskFactors` と `wasBad: Bool`。体調記録（`HealthCheckIn`）と同時刻の気象からの要因算出・突き合わせはアプリ層の責務。

### `DeclaredSensitivity: String, Codable, Sendable, Hashable, CaseIterable`

オンボーディングの体質申告（設計書 §6.5）。`pressure`（気圧の 2 要因を傾ける）/ `rain` / `humidity` / `temperatureSwing`。**rawValue は保存キーなので変更禁止。**

### `PersonalRiskModel: Sendable, Equatable`

| メンバ | 内容 |
|---|---|
| 重み 5 つ + `intercept` | logit = Σ 重み × 要因点数 + 切片 |
| `static let generic` | 全重み 1・切片 −4。合計 4pt（注意境界）で確率 0.5 |
| `static func prior(for:)` | 体質申告 → 事前分布モデル。申告要因の重みを 1 → 1.75 に傾ける。空集合なら `.generic` と同一 |
| `static let declarationTilt` | `0.75`。申告 1 件の傾け量 |
| `probability(of:)` | 体調が悪くなる確率。0〜1（**端に飽和しうる**閉区間） |
| `schedulingLevel(for:)` | 通知判定用の個人化レベル |
| `static func fitted(to:prior:priorWeight:)` | MAP 推定。既定 `prior: .generic`、`priorWeight: 24` |
| `weightRange` / `interceptRange` | クランプ範囲 [0, 3] / [−10, 2] |

## 3. 仕様の中心

1. **`.generic` は汎用と完全一致する。** `schedulingLevel` の境界は汎用モデルにおける合計 1・4・7pt の確率を同一式で計算した値なので、境界の等号まで §3.6 のレベル変換と一致する（1296 全組み合わせをテストで固定）
2. **記録ゼロ・事前分布の強さが不正（非正・非有限）なら事前分布をそのまま返す。** 個人化の失敗は常に「申告込みの初期状態」へ倒れる（申告がなければ `.generic`）。渡された事前分布はクランプ範囲へ収めてから使う
3. **体質申告は事前分布であって説明変数ではない。** 申告は本人の中で定数（切片と共線）なので変数としては情報を持たない。申告だけの初日から通知判定に効き、記録が溜まれば縮小推定が申告を上書きする — **申告は初期値、記録が真実**
4. **縮小推定。** 事前分布（既定 `.generic`、申告があれば `prior(for:)`）を中心とした L2 罰則（強さ `priorWeight` ≒ 擬似観測数）。記録が少ないほど事前分布の近くに留まり、n の閾値で挙動が急変しない
5. **符号制約。** 重みは 0 未満にならない（「悪天候ほど安全」という方向の学習を禁止）。上限 3 と切片の範囲は過剰適合と確率の張り付きを抑える保険
6. **決定的。** 乱数・並列なしの射影勾配降下（反復 2000 固定）。同じ入力は同じモデルを返す

## 4. アプリ層の使い方（Plan 2 以降）

```swift
let model = PersonalRiskModel.fitted(to: observations)   // 記録更新時に再学習
// 表示用: RiskAnalyzer.analyze の結果をそのまま使う
// 通知用: schedulingLevel で判定を差し替えた系列を AlertScheduler へ渡す
let schedulingRisks = risks.map { risk in
    HourlyRisk(point: risk.point,
               assessment: RiskAssessment(level: model.schedulingLevel(for: risk.assessment.factors),
                                          score: risk.assessment.score,
                                          factors: risk.assessment.factors),
               pressureChanges: risk.pressureChanges)
}
```

`score` と `factors` は差し替えない — エピソードのピーク選定（スコア比較）と通知本文の内訳は汎用のまま保つ。

## 5. 型では守られていない制約

1. **`schedulingLevel` を画面表示に流さないこと**。個人化が表示に漏れると「なぜこのレベルか」を説明できなくなる（設計書 §6.5 で適用先を通知に限定した理由）
2. 再学習の頻度・観測の保持数はアプリ層が決める。学習コストは観測数に比例（200 件で数秒 × debug、release では数十 ms）
3. 1 タップ記録の選択バイアス（調子が悪い時ほど記録する）は補正していない。相関レポートの文面が記述に留まる理由の一つ

## 6. 未確定

- `priorWeight = 24` と `declarationTilt = 0.75` は設計値であり、実データでの検証を経ていない。v1.1 の有効化前に体調記録の実データで見直すこと
- 観測の重み付け（新しい記録を重くする等）は未導入
- 寝不足・ストレス等の状態変数（設計書 §6.6）は v1.1 の多変量相関エンジンの領分。`SymptomObservation` への追加は欠損の統計設計とセットで行う
