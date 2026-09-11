<!-- /Users/mymac/zutsuu/assets/kiabou/backgrounds/README.md -->
<!-- 背景素材の仕様と使い方。 -->
<!-- アプリ担当者が画像を組み込めるようにするため。 -->
<!-- 関連: index.html, catalog.json, prompts.md -->
# きあぼうの背景11種類

組み込み image_gen で生成した静止画。生成日: 2026-09-11。
3D風のPNG画像であり、編集可能なBlenderシーンやGLBではありません。
生成原画をそのまま保存し、再生成に使った全文は [prompts.md](prompts.md) にあります。

[一覧プレビュー](index.html) / [一括ZIP](kiabou-backgrounds-v2.zip)

| ID | 名前 |
|---|---|
| rainy-cafe | 雨の日の喫茶店 |
| sunset-rooftop | 夕暮れの屋上 |
| moonlit-cove | 月夜の入り江 |
| cloud-bed | 雲の上の寝床 |
| mage-study | 魔法使いの書斎 |
| forest-veranda | 森の縁側 |
| snow-window | 雪の日の窓辺 |
| underwater-garden | 浅瀬の水庭 |
| quiet-library | 小さな図書室 |
| moon-train | おやすみ列車 |
| quiet-sea | きあぼうの海 |

## 組み込み

- 個別PNGは1536×1024、キャラクターを含まない背景。中央寄せで重ねて配置。
- 画像は静止を基本とし、きあぼうの1/fモーションとは別の層に置く。
- 横長3:2で全景が見える。縦長への中央トリミングでは左右の小物が切れるため、実画面で確認。
- 明るさは表示側で調整。一覧の暗め表示は brightness(0.58) saturate(0.8) の見本。
- 文字や体調記録ボタンは画像の外に置き、読みやすさを確保。
- 無地背景と明るさ調整は、記録による解放条件から独立させる。
- 医療効果・症状改善の検証はしていない。感じ方に合わせて選択できる素材として扱う。

このディレクトリは素材と確認ページのみ。アプリ本体への選択機能の組み込みは別途。

