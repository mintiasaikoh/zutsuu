<!-- /Users/mymac/zutsuu/assets/kiabou/personas/README.md -->
<!-- 衣装シリーズの素材と編集用プロジェクトの場所を案内する。 -->
<!-- 実装用モデルと、Blenderで開く元ファイルを見つけやすくするため。 -->
<!-- 関連: catalog.json, index.html, source-project/README.md, build_personas.py -->

# きあぼうの衣装シリーズ

ぎゃる (`gyaru`)・らっぱー (`rapper`)・ぱんく (`punk`)・喫茶店員 (`cafe`)・魔法使い (`mage`)。

各キャラクターのフォルダに以下を保存している。

| ファイル | 用途 |
| --- | --- |
| `costume.blend` | 衣装付きの編集用Blenderプロジェクト |
| `rest.blend` | 寝姿の編集用Blenderプロジェクト |
| `costume.glb` / `.usdz` | 衣装付きの配布用モデル |
| `plain.glb` / `.usdz` | 色だけの配布用モデル |
| `covered.glb` / `.usdz` | 毛布で休む配布用モデル |
| `*.png` / `textures/` | 確認画像・材質画像 |

泳ぐ2種類は元の10ボーン・6秒の`Drift`を使い、寝姿は静止モデル。
衣装は`KiabouOutfit`、元の体は`KiabouMesh`。1/fゆらぎや解放条件はアプリ側で扱う。

## 元のプロジェクト一式

[source-project/](source-project/)に、5種類の編集用原本10個と共通原型2個、
生成スクリプト・依存する共通処理・材質画像を、相対フォルダ構成ごとコピーした。
このフォルダを取り出しても再編集・再生成に必要なファイルが揃う。

説明は[source-project/README.md](source-project/README.md)、
コピー元との一致を確認した一覧は[source-project/manifest.json](source-project/manifest.json)。
同じ内容の`source-project.zip`は手元にだけ置き、Git には入れない（`.gitignore`）。

素材の生成時検査は完了。追加検証`verify_personas.py`は前回の利用上限で停止しており、
この元プロジェクトの保存作業では再実行していない。アプリ実機での確認も未実施。
