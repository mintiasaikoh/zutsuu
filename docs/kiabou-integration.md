# KiabouUI 統合仕様

**この文書が KiabouUI の正典。** RiskEngine の仕様は `docs/riskengine-api.md`、素材の生成方法は `assets/kiabou/README.md` を参照。

最終更新: 2026-09-09

---

## 1. なにか

きあぼう（気圧＋マンボウ。ユーザー命名、素材は Astra 制作）と一体になった **1 タップ体調記録 UI**。製品の肝は体調記録のフィードバックループ（設計書 §6.2）であり、KiabouUI はその入力口を担う。

```
ios/ZutsuuKit/Sources/KiabouUI/
├── HealthCheckIn.swift      # 公開値型（記録 1 件）
├── CheckInModel.swift       # 保存状態遷移（internal）
├── KiabouCheckInView.swift  # 公開 View
├── KiabouStage.swift        # 背景 + 3D 表示
├── KiabouScene.swift        # RealityKit 読み込み
├── PinkMotion.swift         # 1/f ゆらぎ
├── KiabouPalette.swift      # 昼・薄明かり配色
└── Resources/               # kiabou.usdz / covered.usdz / cove.png / preview.png / covered.png
```

RiskEngine と KiabouUI は相互に依存しない。体調と気象の関連付け・学習はアプリ層の責務。

## 2. 公開 API と契約

```swift
public struct KiabouCheckInView: View {
    public init(onRecord: @escaping @MainActor (HealthCheckIn) async throws -> Void)
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
3. **`HealthFeeling` の rawValue（`"good"` / `"bad"`）は変更禁止。** 保存済みデータの互換キー
4. `date` に対応する気象データと一緒に保存するのはアプリ層（学習の説明変数になる）

## 3. UI の意図的な決定

- 「体調の入力に戻る」は表示切り替えであり、**「良い」を保存しない**（画面を戻る操作を回復記録にしない）
- 「悪い」の記録後だけ、きあぼうが毛布にくるまる休む表示になる
- ゆらぎは 0.025〜0.4 Hz の 1/f。Reduce Motion で自動停止、手動の停止ボタンもある。中断復帰時に位置を飛ばさない（delta を 0.1 秒で切り詰め）
- 見え方（入り江背景・薄明かり）は `AppStorage` キー `kiabou.native.cove` / `kiabou.native.dim`。端末の画面輝度は変更しない
- 症状の軽減効果を主張する文言は置かない（設計書 §6.3 の記述主義に従う）

## 4. 素材

`Sources/KiabouUI/Resources/` は `assets/kiabou/` からの**コピー**。原本は Blender ファイルと生成スクリプト（`assets/kiabou/README.md`）。素材を更新したら再生成して同名でコピーし直すこと。二重管理なのは、SwiftPM のターゲット外からリソースを参照できないため。

追加素材（Astra 制作、アプリ実装は未着手）:

- `assets/kiabou/variations/` — 記録日数で解放する着せ替え（設計書 §6.7）。3 外観 × 色/模様 + 小物、検証記録は `verification.txt`
- `assets/kiabou/personas/` — 衣装ペルソナ（ぎゃる・ぱんく等）の試作。採否未定
- `kiabou-wardrobe-v1.zip` は展開済み内容と重複するため git 管理外

## 5. プラットフォーム

View 層（KiabouCheckInView / KiabouStage / KiabouScene / KiabouPalette）は `#if os(iOS) || os(macOS)`。`HealthCheckIn` / `CheckInModel` / `PinkMotion` は全プラットフォームでコンパイルされる。

## 6. 未確定

- **watchOS の 1 タップ記録**（設計書 v1.0 スコープ）は未実装。値型は共有できるが View は別途必要
- **着せ替え（§6.7）と保存後の任意チップ（§6.6）のアプリ実装**は未着手
- **personas 素材の採否**は未定

マスコットは 3 候補（きあぼう・猫・空の精）からきあぼうに確定し、没候補の素材は 2026-09-09 に削除した（git 履歴にも残っていない）。
