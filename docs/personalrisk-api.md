# PersonalRisk API 仕様

**この文書が PersonalRisk の正典。** 設計判断の理由は設計書 §6.5、RiskEngine の仕様は `docs/riskengine-api.md`、体調記録の入力契約は `docs/kiabou-integration.md` を参照。

最終更新: 2026-09-11

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

学習の 1 標本。`factors: RiskFactors` と `wasBad: Bool`。体調記録（`HealthCheckIn`）と同時刻の気象からの要因算出・突き合わせはアプリ層の責務。体調は 3 択（良い・普通・悪い）だが、通知の判定は「悪くなるか」なので学習は二値 — **「普通」は「悪くない」側**（`wasBad = false`）。順序回帰への拡張は記録が溜まってから検討。

### `DeclaredSensitivity: String, Codable, Sendable, Hashable, CaseIterable`

オンボーディングの体質申告（設計書 §6.5）。`pressure`（気圧の 2 要因を傾ける）/ `rain` / `humidity` / `temperatureSwing`。**rawValue は保存キーなので変更禁止。**

### `PressureCorrelationReport: Sendable, Equatable`（2026-09-12）

設計書 v1.0 の「気圧のみ × 記録の単純な相関レポート」。**記述だけ**を返し、予測・評価の語を持たない（§6.3）。

| メンバ | 内容 |
|---|---|
| `static let minimumRecordedDays = 30` | これ未満は `.insufficient(remainingDays:)`。§6.3 の下限を設計値として採用（§11.5 の 5、実データで見直す） |
| `static func make(observations:recordedDays:)` | 要因付きの観測から作る。`recordedDays` には**要因付きの記録がある日数**を渡す（着せ替えの累計日数とは別。全欠測で「準備完了」にしないため。レビュー R20）。気圧が動いた記録（気圧変化 or 絶対気圧の点数 > 0）と穏やかな記録に分け、それぞれの「つらい」の件数と割合を返す |
| `.insufficient(remainingDays:)` / `.ready(Summary)` | `Summary` は `activeCount` / `activeBad` / `calmCount` / `calmBad`、`activeRate` / `calmRate`（0〜1、件数 0 なら nil） |

文面はアプリ層が作る。「気圧が動いていたときの記録 N 件のうち、つらいが X 件」の形に留め、「気圧に弱い」等の評価語は付けない。体質申告には言及しない（ユーザー決定）。
広告による期限付き解放（設計書 §8、7 日間）は 2026-09-12 に Plan 4 と同時に接続した（`AdsCoordinator.unlock(.correlationReport)`）。SDK 未初期化のあいだはボタンを無効にする。

### `PersonalRiskModel: Sendable, Equatable`

| メンバ | 内容 |
|---|---|
| 重み 5 つ + `intercept` | logit = Σ 重み × 要因点数 + 切片 |
| `static let generic` | 全重み 1・切片 −4。合計 4pt（注意境界）で確率 0.5。通知判定の境界の物差し |
| `static let calibrated` | 文献で較正した事前分布の中心（2026-09-11）。重み比 気圧変化 1.0 / 絶対気圧 0.9 / 湿度 1.3 / 降水 0.6 / 気温変動 0.6 を、満点 18pt の logit が汎用と同じになるよう正規化したもの。切片 −4 |
| `static let calibrationRatios` | 上の重み比。文献（仕様書参考文献 [1][4]）からの専門家較正で、導出値ではない |
| `static func prior(for:)` | 体質申告 → 事前分布モデル。`.calibrated` を起点に主要因を +0.75、**気象的に相関する要因を +0.35** 傾ける（雨 → 降水 + 湿度・気圧変化、湿気 → 湿度 + 降水、寒暖差 → 気温 + 気圧変化）。空集合なら `.calibrated` と同一 |
| `static let declarationTilt` / `relatedTilt` | `0.75` / `0.35`。主要因と相関要因の傾け量 |
| `probability(of:)` | 体調が悪くなる確率。0〜1（**端に飽和しうる**閉区間） |
| `schedulingLevel(for:)` | 通知判定用の個人化レベル |
| `static func fitted(to:prior:priorWeight:)` | MAP 推定。既定 `prior: .calibrated`、`priorWeight: 24` |
| `weightRange` / `interceptRange` | クランプ範囲 [0, 3] / [−10, 2] |

## 3. 仕様の中心

1. **`.generic` は汎用と完全一致する。** `schedulingLevel` の境界は汎用モデルにおける合計 1・4・7pt の確率を同一式で計算した値なので、境界の等号まで §3.6 のレベル変換と一致する（1296 全組み合わせをテストで固定）
1a. **`.calibrated` は汎用から 1 段以上ずれない**（2026-09-11、集団データの効果量を取り込む決定）。0pt と 18pt の logit は汎用と同一で、全 1296 組み合わせで通知判定と表示レベルの差は最大 1 段（テストで固定）。記録ゼロの通知判定が表示と僅かにずれることは、母集団の証拠に沿う代償として受け入れた（設計書 §6.5）
2. **記録ゼロ・事前分布の強さが不正（非正・非有限）なら事前分布をそのまま返す。** 個人化の失敗は常に「申告込みの初期状態」へ倒れる（申告がなければ `.calibrated`）。渡された事前分布はクランプ範囲へ収めてから使う
3. **体質申告は事前分布であって説明変数ではない。** 申告は本人の中で定数（切片と共線）なので変数としては情報を持たない。申告だけの初日から通知判定に効き、記録が溜まれば縮小推定が申告を上書きする — **申告は初期値、記録が真実**
3a. **気象要因の相関を大前提に置く**（2026-09-10、ユーザー指摘）。雨の日は湿度が高く、低気圧・気圧の変化を伴うことが多い。本人が名指しした要因が実際の機序とは限らないため、申告の傾けは主要因＋相関要因に分配する。どれが本当に効いているかは記録が溜まってから回帰が切り分ける（説明変数側の共線は縮小推定が抑える）
4. **縮小推定。** 事前分布（既定 `.calibrated`、申告があれば `prior(for:)`）を中心とした L2 罰則（強さ `priorWeight` ≒ 擬似観測数）。記録が少ないほど事前分布の近くに留まり、n の閾値で挙動が急変しない
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

- `calibrationRatios` は文献の効果量（gain・OR）を同じ物差しに乗せられないため、比としての専門家較正に留まる。実データでの見直し対象
- `priorWeight = 24` と `declarationTilt = 0.75` は設計値であり、実データでの検証を経ていない。v1.1 の有効化前に体調記録の実データで見直すこと
- 観測の重み付け（新しい記録を重くする等）は未導入
- 寝不足・ストレス等の状態変数（設計書 §6.6）は v1.1 の多変量相関エンジンの領分。`SymptomObservation` への追加は欠損の統計設計とセットで行う
