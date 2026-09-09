<!-- /Users/mymac/zutsuu/assets/kiabou/variations/implementation-handoff.md -->
<!-- 実装担当の変更時点で、既存素材と未完成コードの状態を記す。 -->
<!-- 下書きを動作確認済みの統合コードと誤認しないようにするため。 -->
<!-- 関連: ../README.md, README.md, ../../../../ios/ZutsuuKit/Package.swift -->

# 実装の引き継ぎ

ユーザーの指示により、実装は別担当（fable5）へ移管。こちらはアセット案を担当する。

## 現在の状態

- `ios/ZutsuuKit/Sources/KiabouUI/`のSwiftファイルは**作成途中・未コンパイル・未検証**。
- 未完成ターゲットで既存のパッケージを壊さないよう、こちらが追加した`Package.swift`の登録は取り消した。
- `KiabouUI/Resources`への素材同梱と`KiabouUITests`は未作成。
- 体調のDB保存、個人の傾向の学習、通知への反映は未実装。
- 下書きの`KiabouCheckInView`は、必須の非同期`onRecord`をホストへ渡す設計。
  保存完了後にだけ記録完了を表示し、「悪い」なら休む姿に切り替える想定。
- `体調の入力に戻る`は表示だけを切り替え、回復記録を作らない。
- `onRecord`の失敗・再試行・重複防止、3D読込と画面ライフサイクルは未検証。

## 使える元素材

- `assets/kiabou/kiabou.usdz`: 原型の泳ぐ3D素材。
- `assets/kiabou/covered.usdz`: 既存の寝姿から今回書き出した静止素材。
  USDのY-up・4メッシュを検査済み。RealityKit上の表示確認は未実施。
- `assets/kiabou/export_rest_usdz.py`: 寝姿USDZの再生成スクリプト。
- `assets/kiabou/cove.png`: 静止した入り江。
- `assets/kiabou/preview.png`, `covered.png`: 3D読込中・失敗時の画像候補。
- `assets/kiabou/index.html`ほか: 既存のブラウザ試作。

実装担当が判断できるよう、Swiftの下書きは削除せず残した。
既存のリスクエンジンと、その未コミット変更には手を加えていない。
