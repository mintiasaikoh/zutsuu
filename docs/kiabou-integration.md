# KiabouUI 統合仕様

**この文書が KiabouUI の正典。** RiskEngine の仕様は `docs/riskengine-api.md`、素材の生成方法は `assets/kiabou/README.md` を参照。

最終更新: 2026-09-09

---

## 1. なにか

きあぼう（気圧＋マンボウ。ユーザー命名、素材は Astra 制作）と一体になった **1 タップ体調記録 UI**。製品の肝は体調記録のフィードバックループ（設計書 §6.2）であり、KiabouUI はその入力口を担う。

```
ios/ZutsuuKit/Sources/KiabouUI/
├── HealthCheckIn.swift        # 公開値型（記録 1 件）
├── CheckInModel.swift         # 保存状態遷移と休む表示（internal）
├── KiabouQuickCheckIn.swift   # 公開 View。ホーム埋め込み版（アプリが使うのはこちら）
├── KiabouCheckInView.swift    # 公開 View。全画面版（アプリ未使用、watchOS 向けに保持）
├── RecordButton.swift         # げんき／ふつう／つらい の記録ボタン
├── KiabouStage.swift          # 背景 + 3D 表示
├── KiabouScene.swift          # RealityKit 読み込み
├── KiabouAmbientBackdrop.swift # 背面遊泳モード
├── KiabouOutfit.swift         # 着せ替えと解放条件
├── KiabouScenery.swift        # 背景と解放条件
├── PinkMotion.swift           # 1/f ゆらぎ
├── KiabouPalette.swift        # 昼・薄明かり配色
├── Resources/                 # USDZ（泳ぐ: 原型 + 着せ替え 6 + ペルソナ 5。休む: 原型・ペルソナは covered、
│                              #   着せ替えは rest-body 6 + bed + pillow 3 + blanket 3）、背景 JPEG 11、cove/preview/covered PNG
└── Resources/Localizable.xcstrings  # 5 言語（キーは日本語。appcore-api.md §5）
```

RiskEngine と KiabouUI は相互に依存しない。体調と気象の関連付け・学習はアプリ層の責務。

## 2. 公開 API と契約

```swift
public struct KiabouCheckInView: View {          // 全画面版（アプリ未使用、watchOS 向けに保持）。見え方の設定を含む
    public init(onRecord: @escaping @MainActor (HealthCheckIn) async throws -> Void)
}
public struct KiabouQuickCheckIn: View {         // ホーム埋め込み版。ステージ + 3 ボタン + 寝るボタン + 状態 + 累計日数
    public init(recordedDays: Int? = nil, showsStage: Bool = true,
                onRecord: @escaping @MainActor (HealthCheckIn) async throws -> Void)
}
public struct KiabouPalette: Sendable {          // 3 色 + 紙白。アプリ全体が共有する配色
    public init(dim: Bool)
    public var page, card, ink, muted, primary, onPrimary: Color
}
public struct HealthCheckIn: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let feeling: HealthFeeling  // .good / .bad
}
```

アプリ層が守ること:

1. **`onRecord` が正常終了したときだけ保存成功とみなされる。** 例外を握りつぶして戻ると、保存できていない記録が「記録しました」と表示される
2. **同じ `id` の再試行を重複保存しない。** 保存結果が不明なまま再試行された場合、UI は同じ `id`・`date` を渡し直す（`CheckInModelTests` が固定）
3. **`HealthFeeling` の rawValue（`"good"` / `"normal"` / `"bad"`）は変更禁止。** 保存済みデータの互換キー。
   3 択は 2026-09-10 のユーザー決定（`.normal` を追加）。
   **記録は休む姿を切り替えない**（2026-09-11 ユーザー決定。以前は `.bad` で自動的に休んだ）。
   休むのは本人が「きあぼうと寝る」を押したときだけ（`CheckInModel.rest()`）。つらい時でも、
   さまよって泳ぐ・揺れる姿に癒されることがあるため、休ませるかは本人が選ぶ。
   ボタンは 3 つとも同じ色（2026-09-11 ユーザー決定）。以前は `.bad` だけ塗りつぶしだったが、
   既定の選択肢に見えて「つらい」へ誘導し、選択バイアスを UI が助長するためやめた。
   表示名は「げんき／ふつう／つらい」（`label`）。「良い/悪い」は評価の語で硬いため、
   本人の感じ方に寄せた言葉にした（ユーザー要望）。完了文も「記録したよ。」ときあぼうの語り口で統一。
   学習（PersonalRisk）は「悪い」か否かの二値で、`.normal` は「悪くない」側に入れる
4. `date` に対応する気象データと一緒に保存するのはアプリ層（学習の説明変数になる）

## 3. UI の意図的な決定

### 3.0 記録の入口はホームのみ（2026-09-10、ユーザー決定）

記録タブはホームの 1 タップ記録と機能が重複していたため廃止し、**「きあぼう」タブ**に改めた。
タブの役割は (1) 着せ替え、(2) 見え方の設定、(3) 記録ログの確認。記録ボタンはホームだけに置く。
`KiabouCheckInView`（全画面の記録ビュー）はアプリから外れたが、watchOS 等で使い得るため
パッケージには残す。

### 3.2 着せ替え（設計書 §6.7 の実装）

- `KiabouOutfit` が外観と解放条件を定義する。原型（0 日）、色だけ 3 種（累計 3 日）、
  模様あり 3 種（累計 7 日）。**`id` は AppStorage の保存キー（`kiabou.outfit`）なので変更禁止**。
  未知の id は原型に倒す
- 泳ぐ姿・休む姿の USDZ 各 6 種を `Resources/` に同梱（`swim-{family}-{style}.usdz` /
  `covered-{family}-{style}.usdz`、assets/kiabou/variations からのコピー、計約 9MB）。
  素材の同梱漏れはテスト（`KiabouOutfitTests.resourcesAreBundled`）で防ぐ
- **衣装ペルソナ 5 種を採用**（2026-09-11、ユーザー要望）: ぎゃる・ぱんく・かふぇ・まほうつかい・らっぱー。
  id は `{persona}-costume`、素材は assets/kiabou/personas/{persona}/costume.usdz と covered.usdz を
  同じ命名でコピー（計約 10MB、`usdchecker --arkit` 全件合格）。色だけの `plain` は同梱しない。
  解放は累計 14 日（模様の次の段。設計値で、ユーザー判断で変えてよい）
- **寝具の交換**（2026-09-12、設計書 §6.7 の「小物」）: `KiabouBedding` が枕と毛布の色系統を持つ
  （`kiabou.pillow` / `kiabou.blanket`、値は `match`（おそろい）か `kasumi` / `shizuku` / `komorebi`）。
  かすみ・しずく・こもれびの姿で休むときは `covered` ではなく **rest-body + bed + pillow + blanket を
  同じ親に無変換で組む**（`assets/kiabou/variations/ASSETS.md` の手順。中心合わせは組んだ親に 1 回だけ）。
  原型・衣装ペルソナは部品素材がないため `covered` のまま（寝具の選択は効かない旨を画面に添える）。
  枕・毛布の解放はその色の姿（累計 3 日）と同じ。`covered-{family}-{style}.usdz` は組み立てに置き換えたので同梱から外した
- ロック中の表示は「あと N 日」の予告だけ。派手な演出や記録を迫る文言は出さない（§6.7）
- 解放判定の記録日数はきあぼうタブが SwiftData から直接数える（予報の取得を待たない）
- **記録ログには日時・げんき/ふつう/つらいに加えて、その時の天気の特徴を添える**（2026-09-10、ユーザー要望）。
  記録時に `HourlyRisk` の生値（レベル・気圧 hPa・3 時間変化・湿度%・降水確率%・気温℃）を
  `CheckInRecord` に optional で保存し、「安心 · 1018 hPa · 3時間で1hPa上昇 · 23℃」の形で出す。
  生値のない古い記録は要因名だけ（「高い湿度 · 降水」）。文面は記述のみで評価語を付けない

### 3.3 背景の選択（2026-09-11、ユーザー制作の素材 11 種）

- `KiabouScenery` が背景と解放条件を定義する。無地（0 日）・入り江（0 日、従来の背景）・
  ユーザー制作の 11 種（assets/kiabou/backgrounds、`catalog.json` の順に 5 種が累計 5 日、6 種が累計 10 日。
  設計値でユーザー判断で変えてよい）。**`id` は AppStorage の保存キー（`kiabou.scene`）なので変更禁止**。
  未知の id は入り江に倒す
- 素材は PNG 1536×1024（各約 1.9MB）を JPEG 品質 80 に変換して `Resources/scene-{id}.jpg` として同梱
  （11 枚で約 2.3MB。PNG のままだと 21MB 増えるため）。同梱漏れはテスト（`KiabouSceneryTests`）で防ぐ
- 薄明かり（`kiabou.native.dim`）は背景に関わらず同じ処理（彩度 0.7・黒 57% 重ね）。快適さの設定は
  解放条件から独立（設計書 §6.7）
- 従来の `kiabou.native.cove`（入り江オン/オフ）は `kiabou.scene` に置き換えた。未リリースのため移行処理なし
- 縦長トリミングで左右の小物が切れる素材があるが、ステージは横長カードなので許容（素材 README の注意）

### 3.1 背面遊泳モード（2026-09-10、ユーザー提案）

きあぼうをカードの中に固定せず、**UI の後ろを縦横斜めにゆっくり泳がせる**モード。

- `KiabouAmbientBackdrop` を画面の最背面に置き、カードを半透明にして向こう側を見せる
- 動きは緩やかな方向の彷徨（進行方位が 1/f で徐々に変わる）＋既存の 1/f の揺れ。画面端では跳ね返る（瞬間移動で位置が飛ぶと不自然なため）。
  縮尺 0.6、折り返しの範囲は ±0.05 / ±0.19（視野の半幅 ≈0.13・半高 ≈0.29 から体の半径と揺れ幅を引いた値。2026-09-12 に体が端で切れる問題を直した）
- **読み込み完了は body で読む**（2026-09-12 修正）。`update` クロージャの中でしか読まないと、読み込みが onAppear より後に終わったとき update が再実行されず、購読されないまま静止する
- 有効時はホームの記録カードのステージを隠す（きあぼうが二匹に見えないように）
- Reduce Motion 時は無効化し、従来のカード内表示に戻す
- 記録直後（休む状態）でも背面のきあぼうは泳ぎ続ける。休む姿はカード内表示のときだけ
- 設定の「きあぼう」セクションでオン/オフ（`AppStorage` キー `kiabou.ambient`、既定オフ）

- 「体調の入力に戻る」は表示切り替えであり、**「良い」を保存しない**（画面を戻る操作を回復記録にしない）
- 休む表示（毛布にくるまる）は「きあぼうと寝る」ボタンで本人が選ぶ。記録は表示を変えない（2026-09-11）
- ゆらぎは 0.025〜0.4 Hz の 1/f。Reduce Motion で自動停止、手動の停止ボタンもある。中断復帰時に位置を飛ばさない（delta を 0.1 秒で切り詰め）
- 見え方（背景・薄明かり）は `AppStorage` キー `kiabou.scene` / `kiabou.native.dim`。端末の画面輝度は変更しない。
  `dim` はステージの見え方にだけ効き、文字・ボタンの配色は親カードと同じ OS の明暗で決める（レビュー R15）
- 症状の軽減効果を主張する文言は置かない（設計書 §6.3 の記述主義に従う）

## 4. 素材

`Sources/KiabouUI/Resources/` は `assets/kiabou/` からの**コピー**。原本は Blender ファイルと生成スクリプト（`assets/kiabou/README.md`）。素材を更新したら再生成して同名でコピーし直すこと。二重管理なのは、SwiftPM のターゲット外からリソースを参照できないため。

追加素材:

- `assets/kiabou/variations/` — 記録日数で解放する着せ替え（設計書 §6.7、Astra 制作）。3 外観 × 色/模様 + 小物、検証記録は `verification.txt`。色/模様の 6 種は 2026-09-10、寝具（枕・毛布）の交換は 2026-09-12 に同梱済み
- `assets/kiabou/personas/` — 衣装ペルソナ 5 種。2026-09-11 に採用し `costume` / `covered` を同梱
- `assets/kiabou/backgrounds/` — ユーザー制作の背景 11 種（PNG 原画・プロンプト・catalog.json）。
  2026-09-11 に採用し JPEG 変換して同梱。`kiabou-backgrounds-*.zip` は展開済み内容と重複するため git 管理外
- `kiabou-wardrobe-v1.zip` は展開済み内容と重複するため git 管理外

## 4.5 実装上の罠（2026-09-10）

`KiabouScene` は `@Observable` で、`RealityView` の `update:` 内から `stop()` / `setMotion` を呼ぶ。
内部状態（`enabled`・`subscription` など）を観測対象にすると「書き換え → 再描画 → `update` → 書き換え」の
無限ループでメインスレッドが止まる（ホームの ScrollView に埋め込んだ時点で顕在化、`sample` で確認）。
画面が観測してよいのは `loadedResting` と `failed` だけで、他は `@ObservationIgnored`。新しい状態を足すときも同じ。

**`AnimationPlaybackController.speed` を毎フレーム設定しないこと。** RealityKit の
speed setter は内部で毎回 os_log を発行し、毎フレーム × コントローラ数だとログ処理だけで
メインスレッドが飽和して UI ごと固まる（記録タブを開いてシーンが 2 つになった時点で顕在化。
`sample` でスタックの約 8 割が logging だった）。`tick` は 0.3 秒ごとに間引いて設定する。
同じ理由で `playAnimations` はアニメーションを持つ階層で再帰を止める — 子孫まで下りると
同じアニメーションを骨の数だけ重複再生してコントローラが膨らむ。

**SwiftUI の `Image(_:bundle:)` で SPM のリソース PNG を読まないこと。** アセットカタログしか
探さず、バンドル直下の PNG では**静かに空を描く**（エラーも nil もない。入り江の背景が
出なかった原因）。`UIImage(named:in:with:)` / `Bundle.image(forResource:)` 経由で読む
（`KiabouStage.bundledImage(_:)`）。

## 5. プラットフォーム

View 層（KiabouCheckInView / KiabouStage / KiabouScene / KiabouPalette）は `#if os(iOS) || os(macOS)`。`HealthCheckIn` / `CheckInModel` / `PinkMotion` は全プラットフォームでコンパイルされる。

## 6. 未確定

- **watchOS の 1 タップ記録**は 2026-09-12 に実装（`ios/ZutsuuWatch`、`docs/plans/2026-09-12-watchos-plan5.md`）。Watch は `HealthFeeling` の値型だけを使い、View は Watch 専用。実機での到達保証とコンプリケーション表示は未確認
- **保存後の任意チップ（§6.6）のアプリ実装**は未着手（v1.1）
- personas の `plain`（色だけ）版の採否は未定

マスコットは 3 候補（きあぼう・猫・空の精）からきあぼうに確定し、没候補の素材は 2026-09-09 に削除した（git 履歴にも残っていない）。
