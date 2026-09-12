<!-- /Users/mymac/zutsuu/assets/kiabou/personas/source-project/README.md -->
<!-- 衣装シリーズの編集・再生成に必要な元プロジェクトを説明する。 -->
<!-- フォルダを移しても原型と生成スクリプトの依存関係を保つため。 -->
<!-- 関連: manifest.json, ../README.md, kiabou/personas/build_personas.py -->

# きあぼうの元プロジェクト

作成時のファイルを、元の相対フォルダ構成でコピーした保存版。
コピー元とのSHA-256一致を検査済み。一覧は`manifest.json`。
Python先頭の絶対パスコメントはコピー元の所在を示す。

## Blenderで編集

`kiabou/personas/`内の各フォルダを開く。

| フォルダ | キャラクター |
| --- | --- |
| `gyaru` | ぎゃる |
| `rapper` | らっぱー |
| `punk` | ぱんく |
| `cafe` | 喫茶店員 |
| `mage` | 魔法使い |

- `costume.blend`: 衣装、体、骨格、泳ぎ、確認用のカメラ・照明を含む編集用原本。
- `rest.blend`: 衣装を外して毛布で休む姿。衣装はレンダー非表示の状態で残る。
- `textures/`: 色・模様の画像。生成時にはBlenderファイルへもパックしている。

共通原型は`kiabou/kiabou.blend`、共通寝床は`kiabou/kiabou-rest.blend`。
制作環境はBlender 5.2.1。

## 再生成

この`source-project`フォルダをカレントディレクトリにして実行する。
Pythonが使う共通処理も同梱してあり、元のリポジトリへの参照は不要。

```sh
blender --background --python kiabou/personas/build_personas.py
```

実行するとこの保存版の中にGLB・USDZ・確認画像を生成し、同名のBlender原本を上書きする。
手作業で編集した後は、別名で保存してから再生成する。

この保存作業で確認したのはファイルの存在とコピー内容の一致。
前回、利用上限で止まった`verify_personas.py`の追加検証は、この作業では再実行していない。
