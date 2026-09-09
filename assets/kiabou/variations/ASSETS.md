<!-- /Users/mymac/zutsuu/assets/kiabou/variations/ASSETS.md -->
<!-- 生成済みの着せ替え素材の構成、配置、再生成方法を説明する。 -->
<!-- 実装担当が原点やUVを壊さず、アプリへ組み込めるようにするため。 -->
<!-- 関連: catalog.json, build_variations.py, verify_assets.py, README.md -->

# きあぼう着せ替え素材 v1

ルート: `assets/kiabou/variations/`。全モデルをGLBとUSDZの両形式で用意。
**3色 × 色だけ/模様あり = 6種類の外観**。病状・学習精度・解放条件は素材に含めない。
アプリ側で本人の選択に対応するファイルを読み込む。

| ID | 色・模様 | 枕 | 毛布 |
| --- | --- | --- | --- |
| `kasumi` | 霞色、上半身と上ヒレにゆるい帯 | 雲形 | 青灰色、幅広の帯 |
| `shizuku` | 青緑、背中に2つの雫 | 雫形 | 青緑 |
| `komorebi` | 灰青色、砂色と淡緑の色面 | 楕円 | 灰色、淡緑の縁 |

## ファイル

`{family}`は上表のID、`{style}`は`plain`（色だけ）または`pattern`（模様あり）。

| パス（拡張子省略） | 内容 | 数 |
| --- | --- | --- |
| `{family}/{style}/swim` | 骨格付き、泳ぐきあぼう | 6 |
| `{family}/{style}/covered` | 寝姿＋寝床＋同系統の枕・毛布を組んだ静止モデル | 6 |
| `{family}/{style}/rest-body` | 交換用の寝姿の体だけ | 6 |
| `{family}/accessories/pillow` | 交換用の枕 | 3 |
| `{family}/accessories/blanket` | 体にかかる形で固定した毛布 | 3 |
| `shared/bed` | 共通の寝床 | 1 |

合計25モデル × 2形式 = **50ファイル**。全モデル合計約24.8 MB。
通常はアプリで使う片方の形式だけを同梱する。
泳ぐモデルはGLB約0.55–0.58 MB、USDZ約0.72–0.74 MB。
各モデルの正確なサイズ・メッシュ数・パスは`catalog.json`に記載。

- `{family}/{style}/swim.blend`, `rest.blend`: テクスチャをパックした編集用原本。
- `{family}/{style}/swim.png`, `covered.png`: 生成した3Dからレンダリングした確認画像。
- `{family}/{style}/textures/body.png`, `fins.png`: 共通UVに対応したsRGB色テクスチャ。
- `{family}/accessories/blanket.png`: 毛布の色テクスチャ。
- `concept-sheet.png`: デザインの参考ラフ。実装用画像ではない。

## アニメーションと姿勢

泳ぐ素材は原型の10ボーン・`Drift`・6秒ループを保持する。
上下のヒレ、胸びれ、後端、浮遊、まばたきを含む。
各外観の頂点・重み・UVは一致する。顔の形と黒い材質は原型のまま。

GLBのアニメーション名は`Drift`。USDZにも同じ骨格アニメーションを含むが、
RealityKitでのリソース名はローダー側で決まるので名前固定の検索を前提にしない。
`availableAnimations`を実際に持つEntityを確認してループ再生する。
`covered`、`rest-body`、寝具にはアニメーションを含めない。
**1/fゆらぎはアプリ側で加える動き**で、この素材のキーフレームには焼き込んでいない。

## 枕や毛布を別の色にする

全モデルはY-up、単位メートル。寝具と寝姿は同じシーン原点に書き出してある。
次の4つを同じ親Entityへ、追加の平行移動・回転・拡大縮小なしで配置する。

```text
RestScene
  ├─ kasumi/pattern/rest-body.usdz
  ├─ shared/bed.usdz
  ├─ shizuku/accessories/pillow.usdz
  └─ komorebi/accessories/blanket.usdz
```

これで、かすみの体＋雫の枕＋こもれびの毛布を組み合わせられる。
**部品ごとにバウンディングボックスの中心へ移動しないこと。**
表示位置を中央へ寄せるなら、4つを組んだ親Entityに対して一度だけ行う。
同じ理由で、読み込んだルートの内部変換をリセットしない。
`covered`はすでに4部品を含むので、その上から追加の寝具を重ねない。

## 材質を差し替える場合

材質名は`Kiabou.Body`、`Kiabou.Fins`、`Kiabou.Tail`、`Kiabou.Face`。
体の模様は側面投影の共通UVへ焼き込んであり、寝姿にも同じUVを保持している。
目と口の`Kiabou.Face`は変更しない。

**従来の`assets/kiabou/kiabou.glb`のUVとは異なる。**
今回の`body.png`を従来モデルにそのまま貼ることはできない。
今回の6種類のモデル間では共通。原型を残すなら原型ファイルを別の選択肢として使う。
最初の統合では材質の編集を省き、外観に対応するモデルを読み替えるのが簡単。

## 検証

生成時に以下を検査し、`verify_assets.py`でも生成済みファイルを再検査する。

- 全25組のGLB/USDZを読み込み、Y-up・メートル単位・テクスチャ同梱を確認。
- カメラ・照明を配布モデルへ含めない。
- 6種類の骨格・UV互換性と、GLB/USDのループ端の一致。
- USDZの既定姿勢にも開始フレームの変換を設定し、再生前後でサイズが変わらないことを検査。
- GLBの実キーから、上下ヒレ・浮遊・まばたきの動きと6秒の長さを検査。
- 分離した4部品と完成セットのワールド座標の範囲が一致することを照合。
- ブラウザで3種類の模様、寝姿、枕の実GLBを目視確認。

RealityKitでの実機表示、アプリの着せ替え操作との接続は実装担当の確認範囲。

## 再生成とプレビュー

リポジトリ直下から実行。同名の生成済みバリエーションを上書きする。
原型の`kiabou.blend`、`kiabou-rest.blend`は読み取りのみ。

```sh
blender --background --python assets/kiabou/variations/build_variations.py
blender --background --python assets/kiabou/variations/verify_assets.py
python3 -m http.server 8767 --bind 127.0.0.1 --directory assets/kiabou
```

プレビュー: `http://127.0.0.1:8767/variations/`。
制作はBlenderの元メッシュと自前の材質・形状生成で行った。
比較ラフの画像生成は`prompt.md`、3D制作の処理は上記Pythonファイルに保存している。
