<!-- /Users/mymac/zutsuu/docs/reviews/2026-09-12-codebase-review.md -->
<!-- 役割: コードベース全体のレビュー結果と修正の受け入れ条件。 -->
<!-- 存在理由: Claude が根拠・優先順位・検証方法を引き継いで修正するため。 -->
<!-- 関連: docs/riskengine-api.md, docs/appcore-api.md, docs/personalrisk-api.md, ios/ZutsuuApp/Sources/ForecastPipeline.swift -->

# コードベースレビュー — 2026-09-12

対象: `/Users/mymac/zutsuu`、HEAD `89095b5`。実装の修正は行っていない。開始時から存在した未追跡ファイルも変更していない。

**総評: 純粋な計算ロジックと、その周囲の実運用の品質に差がある。現状を通知・保存の信頼性が確保された状態とは評価できない。** 既存テストは通るが、時間経過、再起動、配信済み通知、保存失敗、通信復旧をまたぐ処理が不足している。優先度 P1 が4件、P2 が19件。P0 に相当する問題は今回確認していない。

## 範囲・評価・検証

構成全体を走査し、TypeScript 通知処理、iOS アプリ全ソース、RiskEngine、AppCore、PersonalRisk、KiabouUI、広告、Watch、ウィジェット、パッケージ・CI設定を読んだ。仕様と主要な境界テストを照合した。周辺の Web ビューア、アセット生成・検証スクリプト、平年値生成処理も確認したが、Blender の全造形処理やバイナリ素材の見た目を網羅的に監査したものではない。未追跡の `source-project/` は配布用複製として本体レビューから除外した。

| 観点 | 評価 | 理由 |
|---|---|---|
| 正確性 | 要優先修正 | 通知の重複・設定無視・記録消失経路・時間軸の取り違え |
| セキュリティ・プライバシー | 要改善 | 体調を公開ログへ出力。広告側が健康データ型へ依存しない分離は良い |
| 性能 | 要改善 | MainActor 上の全履歴再学習。長期利用時のコストを制御していない |
| 保守性 | おおむね良好・統合部に弱点 | 小さな Swift モジュールと仕様書は有用。一方、仕様自体が不具合を固定する箇所がある |
| テスト | 単体は良好・統合が不足 | 既存テスト通過と、本レビューの再現可能な不具合が両立している |

実施結果:

- `./node_modules/.bin/tsc --noEmit`: 成功。
- ZutsuuKit の `swift test`: debug **171件**、release **170件**成功。
- ZutsuuAds の `swift test`: **8件**成功。macOS 上の AdPolicy テストであり、広告 SDK の画面表示を検証した結果ではない。
- 追跡対象の Python 16本、JavaScript 6本、JSON 6件、String Catalog 7件: 構文検査成功。翻訳品質やアセットの妥当性の証明ではない。
- 一時領域で現行の純粋ロジックを使い、通知再予約・個人化ピーク・TypeScript の時刻処理等を再現。リポジトリのテストや実装には追加していない。
- Swift の初回実行は標準キャッシュへの書き込み制限で失敗。キャッシュを `/tmp` に変更し、SwiftPM の子プロセス用 sandbox を無効化した再実行で成功した。コード起因の失敗として扱っていない。
- アプリの実機・シミュレータ操作、iOS/watchOS アプリのビルド、LINE送信、広告配信、DB操作・マイグレーションは実施していない。`npm run check` は通知送信を伴いうるため実行していない。

以下の「再現」は一時ハーネスで実行したもの。「静的確認」は制御フローを確認したもので、端末での発生頻度まで測定したものではない。P1 は中核機能の信頼性を損なう問題、P2 は条件付きの不具合・性能・運用品質の問題とする。

## P1 — 優先して修正

### R01. 配信済みの事前通知を何度でも再予約する

- 根拠: [AlertScheduler.swift:250](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/AlertScheduler.swift:250)、[NotificationReconciler.swift:68](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/NotificationReconciler.swift:68)、[ForecastPipeline.swift:95](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:95)。**再現済み。**
- 14:00 の上昇を12:30に通知した後、12:45に再計算すると、12:46の通知を再追加する。保留中の予約しか参照せず、配信済みのエピソードを識別しないため。記録操作でも再計算される。
- 影響: 同じ事象の通知が記録・更新のたびに再送される。識別子が安定していても、既に保留一覧から消えた通知には重複防止が効かない。
- 修正方針: 配信・通知済みエピソードの扱いを定義し、予約照合へ渡す。既存通知の消去や再起動をまたいでも再送しない方針を明確にする。永続化方式の変更が必要なら先に提案する。
- 受け入れ条件: 12:30配信後、12:45の更新・13:00の記録・再起動で同じエピソードを再通知しない。まだ一度も通知していない直前の上昇は通知する。

### R02. 静穏時間の変更が同じエピソードの予約に反映されない

- 根拠: [NotificationReconciler.swift:58](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/NotificationReconciler.swift:58)、[AlertNotifications.swift:34](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/AlertNotifications.swift:34)。**再現済み。**
- 01:00の事象を08:30に通知する予約を作り、静穏時間の終了を10:00へ変更する。新しい予定は10:00だが、識別子が同じため `cancel=0 / add=0` となり08:30に鳴る。入口が過去になった wakeUp はさらに無条件で温存される。
- 影響: ユーザーが「鳴らさない」と設定した時間に通知する。レベル・本文の更新も同じ照合で失われる。
- 修正方針: 同じIDでも発火日時・通知内容の差分を比較する。過去の入口を持つ wakeUp の保護と、ユーザーによる設定変更を区別する。正典の「同じ識別子なら温存」も改訂が必要。
- 受け入れ条件: 終了時刻の延長・短縮・静穏時間の無効化で予約が一致する。変化していない予約は不要に付け替えない。

### R03. Watch の転送成功後、iPhone の保存失敗で記録が失われる

- 根拠: [WatchSession.swift:44](/Users/mymac/zutsuu/ios/ZutsuuWatch/Sources/WatchSession.swift:44)、[WatchSessionBridge.swift:39](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/WatchSessionBridge.swift:39)。**静的確認。**
- Watch は到達可能時に返信不要の `sendMessage` を使う。iPhone は受信後に別の Task で保存し、失敗するとログを出すだけ。transport が成功した後の `store.save` 失敗は Watch の通信エラーハンドラへ戻らない。`transferUserInfo` 経由でも、受信後の保存失敗を回復する処理はない。
- 影響: Watch では「送ったよ」と出た記録を再送・回復できない。受信と永続保存を同一の成功として扱っている。
- 修正方針: 保存成功の ACK と、未確認記録を再送できる仕組みを設計する。同じUUIDでの重複防止を維持する。DB変更が必要なら実施せず提案に留める。
- 受け入れ条件: 受信後の保存失敗、アプリ終了、ACK喪失を注入し、最終的に記録が1件だけ保存される。未保存の状態を確認できる。

### R04. LINE版は次の時刻を「現在」と扱い、直近の上昇を見逃す

- 根拠: [src/index.ts:225](/Users/mymac/zutsuu/src/index.ts:225)、[src/index.ts:538](/Users/mymac/zutsuu/src/index.ts:538)。**再現済み。**
- 10:09実行時、`new Date(t) >= now` は11:00を先頭にする。10:00が安心、11:00から注意の入力で `risks[0]=注意` となり、`shouldSendAlert` は `null` を返した。
- 影響: 最も近い上昇を「既に注意」と判断して抑止する。前回実行で先に通知されている可能性はあるが、初回実行・前回失敗・直前の予報変更では見逃しになる。雨のフォールバックと通知時刻にも同じ1スロットのずれがある。
- 修正方針: 現在を含む時間帯と将来を分離し、実日時に基づいて判定する。APIのタイムゾーンを明示的に扱い、UTC環境でも同じ結果にする。
- 受け入れ条件: 毎時00分・09分・59分で「現在」と直近上昇の対応が正しい。JST/UTCの実行環境を変えても結果が一致する。

## P2 — 次に修正

### R05. 深夜の再計算で、同じ朝の wakeUp が2件に増える

- 根拠: [NotificationReconciler.swift:60](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/NotificationReconciler.swift:60)、[AlertScheduler.swift:178](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/AlertScheduler.swift:178)。**再現済み。**
- 01:00と05:00の上昇は最初08:30の1件へ集約される。03:00に再計算すると最初の予約を温存しつつ、05:00を入口とする08:30の予約を追加する。
- 修正方針: 新規予定だけでなく温存する予約も含め、同じ朝への集約を行う。受け入れ条件: 深夜に何度更新しても、同一の静穏区間について wakeUp は1件だけ。

### R06. 通知設定の変更がネットワーク・位置取得の成功に依存する

- 根拠: [SettingsView.swift:65](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/SettingsView.swift:65)、[ForecastPipeline.swift:68](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:68)。**静的確認。**
- 設定変更は `refresh()` を呼ぶだけで、位置取得・WeatherKitに失敗すると再予約に到達しない。R02を直しても、オフラインでは古い静穏時間の予約が残る。
- 修正方針: 保存済みの予報から通知だけを再計算する経路を用意する。受け入れ条件: 機内モードや位置情報拒否の状態でも、既存予約へ設定変更が反映される。

### R07. 時刻の経過・アプリ復帰だけでは「いま」の表示が更新されない

- 根拠: [TodayView.swift:76](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/TodayView.swift:76)、[RootView.swift:39](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/RootView.swift:39)、[ForecastPipeline.swift:118](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:118)、[WatchSession.swift:39](/Users/mymac/zutsuu/ios/ZutsuuWatch/Sources/WatchSession.swift:39)。**静的確認。**
- `Date()` は観測可能な状態ではない。画面表示中の時間境界を更新する仕組みがなく、復帰時の処理も広告だけ。Viewが維持される復帰では `.task` の再実行を保証できない。Watchも同様。
- 修正方針: 時刻依存の表示へ時計を渡し、時間境界で再評価する。active復帰では `refreshIfStale()` を呼ぶ。受け入れ条件: 操作なしで時刻が変わるとレベル・時間別一覧・次の通知・古い要約判定が更新される。

### R08. 「次の通知」が実際の予約・権限・失敗状態と一致しない

- 根拠: [ForecastPipeline.swift:153](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:153)、[NotificationClient.swift:63](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/NotificationClient.swift:63)。**静的確認。**
- `nextAlert` は権限確認・照合・追加の前に新規予定だけから作られる。通知拒否や `add` 失敗でも「通知」と表示し、逆に温存された wakeUp は新規予定に出ないため表示から消える。`try?` によって失敗も呼び出し元へ戻らない。
- 修正方針: 予約処理の結果と実際の保留一覧から表示を作り、拒否・失敗を区別する。受け入れ条件: 許可拒否、追加失敗、温存wakeUpの3ケースで表示と予約が一致し、過去の通知を表示し続けない。

### R09. 予報なしで受信したWatch記録は、気象要因が永久に欠落する

- 根拠: [ForecastPipeline.swift:95](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:95)、[CheckInStore.swift:67](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/CheckInStore.swift:67)。**静的確認。**
- `risks` はメモリのみ。iPhoneのコールド起動時や予報取得前に届いた記録は `risk=nil / hasFactors=false` で保存され、後で予報を得ても補完されない。同じUUIDの再試行も早期returnする。
- 修正方針: 体調の保存を妨げず、気象との関連付けを後から補完する経路を設計する。取得できない古い記録は欠損として示す。受け入れ条件: 保存と予報取得の順序を逆転させても、取得可能な要因が最終的に関連付く。DB変更は別途提案する。

### R10. 体調を記録すると、古い予報の有効期限まで延びる

- 根拠: [ForecastPipeline.swift:98](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:98)、[ForecastPipeline.swift:113](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:113)、[WatchPayload.swift:40](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/AppCore/WatchPayload.swift:40)。**静的確認。**
- `publishWatchContext(now:)` は体調記録時にも予報を取り直さず `updatedAt=現在` とする。6時間の鮮度判定が、予報の取得時刻ではなく最後の記録時刻から始まる。
- 修正方針: 予報の取得日時と要約の送信日時を分け、鮮度には `lastUpdated` を使う。受け入れ条件: 7時間前の予報で体調を記録しても、Watchの古い予報判定が解除されない。

### R11. 個人化したレベルと汎用スコアの順序が違い、ピークを取り違える

- 根拠: [AlertScheduler.swift:228](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/AlertScheduler.swift:228)、[ForecastPipeline.swift:143](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:143)。**再現済み。**
- 最高の汎用 `score` の判定を選び、そこから `targetLevel` を導出する。しかし個人化後のレベルは汎用スコアに対して単調でない。既定の `.calibrated` でも、要因 `[3,0,3,0,0]` の6ptは危険、`[3,0,0,2,2]` の7ptは注意となる。
- 修正方針: 通知区間の最高レベルと、要因説明に使う代表時点の規則を分ける。`personalrisk-api.md` の「scoreを変えない」とピーク規則の整合も見直す。受け入れ条件: 安心→危険→注意の区間が「注意」を最高レベルとして返さない。

### R12. 全履歴の再学習がMainActorを同期的に占有する

- 根拠: [ForecastPipeline.swift:140](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:140)、[PersonalRiskModel.swift:207](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/PersonalRisk/PersonalRiskModel.swift:207)。**計測済み。**
- 記録・更新ごとに全観測×2000反復をUIスレッドで実行する。一時ハーネスの合成観測でdebugは200件約1.16秒、1000件約5.77秒、最適化ありはそれぞれ約12ms・44msだった。これはMac上の参考値であり、iPhoneの実測値ではない。
- 修正方針: 不変の観測配列を作り、学習をMainActor外へ移す。世代管理で古い学習結果の採用を防ぐ。受け入れ条件: 長期利用相当の記録数でも保存ボタン・スクロールが学習完了待ちで停止しない。

### R13. 広告の準備完了を見逃し、ネイティブ広告がロードされない

- 根拠: [NativeAdCard.swift:29](/Users/mymac/zutsuu/ios/ZutsuuAds/Sources/ZutsuuAds/NativeAdCard.swift:29)、[RootView.swift:37](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/RootView.swift:37)。**静的確認。**
- 初回表示時の `isEnabled=false` ではロードせず、その後trueになっても `.onAppear` しか監視していない。同意・SDK初期化は画面描画後なので、この順序は通常起こりうる。
- 修正方針: 表示状態と有効状態の変化を両方監視する。受け入れ条件: 表示後にSDKを準備完了へ切り替えると、1回だけロードされる。

### R14. 広告の初回ロード失敗から復帰できない

- 根拠: [AdMobProvider.swift:28](/Users/mymac/zutsuu/ios/ZutsuuAds/Sources/ZutsuuAds/AdMobProvider.swift:28)、[AdMobProvider.swift:89](/Users/mymac/zutsuu/ios/ZutsuuAds/Sources/ZutsuuAds/AdMobProvider.swift:89)、[AdMobProvider.swift:112](/Users/mymac/zutsuu/ios/ZutsuuAds/Sources/ZutsuuAds/AdMobProvider.swift:112)。**静的確認。**
- 初回ロードに失敗して `rewarded=nil` になると、表示要求は早期returnし、再ロードへ進まない。広告なし状態での再試行経路がない。初期同意の通信失敗も `started=true` によって同一プロセス内でやり直せない。
- 修正方針: 初期化中・初期化済み・在庫なし・失敗を区別し、在庫なし時の再取得を制御する。受け入れ条件: 起動時オフライン→復旧後にリワードを取得でき、失敗時にはボタンを押しても無反応な状態を残さない。

### R15. ホームのカードと記録ビューで配色の基準が異なり、文字が読めなくなる

- 根拠: [TodayView.swift:18](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/TodayView.swift:18)、[KiabouQuickCheckIn.swift:36](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouQuickCheckIn.swift:36)、[KiabouPalette.swift:19](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouPalette.swift:19)。**静的確認。**
- 親のカードはOSのdark/light、子の文字は `kiabou.native.dim` を使う。OSダーク・dim=falseで暗いカードに暗い文字、OSライト・dim=trueで白いカードに淡色の文字となる。
- 修正方針: 記録カードの背景と文字に同じテーマを渡す。受け入れ条件: OS明暗×dimの4組み合わせで、本文・ボタン・保存状態が読めることを画面で確認する。

### R16. ホームの要因説明が気圧の配点を落とす

- 根拠: [TodayView.swift:205](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/TodayView.swift:205)。**静的確認。**
- `FactorText` は絶対気圧の加点を説明せず、気圧変化も3時間値しか見ない。6時間で6hPa、3時間で0hPa等の条件でも「大きな変化はありません。」と出せる。
- 修正方針: 通知側と同様に絶対気圧と1/3/6時間の要因を扱う。受け入れ条件: 絶対気圧のみの加点、1時間・6時間だけの加点で、配点に対応した理由が表示される。

### R17. 気象庁の降水確率を誤った timeSeries から取得している

- 根拠: [src/index.ts:199](/Users/mymac/zutsuu/src/index.ts:199)。**公式レスポンス確認・再現済み。**
- `timeSeries[0].areas[0].pops` を読むが、2026-09-12に確認した[気象庁の東京予報JSON](https://www.jma.go.jp/bosai/forecast/data/forecast/130000.json)では `[0]` は天気・風等、`pops` は `[1]`。対応する構造のfixtureで取得結果は0件だった。
- 修正方針: 配列位置の固定ではなく `pops` を持つ系列と対象地域を選ぶ。欠測値を0%へ変換しない。受け入れ条件: 実際の構造のfixtureで時刻別降水確率が上書きされ、欠測時は元の予報を維持する。

### R18. 朝のLINE通知が2本のworkflowから送られる

- 根拠: [check.yml:7](/Users/mymac/zutsuu/.github/workflows/check.yml:7)、[morning.yml:5](/Users/mymac/zutsuu/.github/workflows/morning.yml:5)、[src/index.ts:782](/Users/mymac/zutsuu/src/index.ts:782)。**静的確認。**
- 毎時のcheckと毎日00:00 UTCのmorningが09時台JSTに走ると、前者は `isMorningBriefingTime()`、後者は `MORNING_MODE` で同じ朝予報を送る。送信済み判定はない。
- 修正方針: 朝通知の担当を一本化する。再実行・pushによる起動を含めた重複方針も決める。受け入れ条件: 同じ日の09時台に両経路が実行されても朝予報は1回だけ送られる。

### R19. 現在のナウキャスト取得失敗を「雨が降っていない」と判定する

- 根拠: [src/index.ts:647](/Users/mymac/zutsuu/src/index.ts:647)。**再現済み。**
- 現在値 `-1`、60分後 `5` のとき、`-1 < 1` により雨の開始通知が成立した。将来値だけ成功していれば現在値の取得失敗を検査しない。
- 修正方針: 両方の取得成功を確認してから開始を判定し、片側欠測はフォールバックまたは不明とする。受け入れ条件: `(-1,5)`、`(0,-1)`、`(-1,-1)` を雨なし状態として扱わない。

### R20. 分析データがないのに、レポートを開く広告視聴を促す

- 根拠: [KiabouTabView.swift:175](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/KiabouTabView.swift:175)、[PressureCorrelationReport.swift:28](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/PersonalRisk/PressureCorrelationReport.swift:28)。**静的確認・純粋関数で確認。**
- 日数は全記録、分析は `hasFactors` のある記録だけ。30日分すべて欠測でも `.ready` となり、「記録は十分」と広告視聴を促した後でデータ0件の結果を出せる。1件だけ関連付いた場合も同じ問題がある。
- 修正方針: 分析可能な記録の日数で準備完了を判断する。着せ替え用の累計日数は分けて維持する。受け入れ条件: 全欠測・一部のみ関連付きでは十分な分析資料があると表示しない。

### R21. 非グレゴリオ暦の端末で、気圧平年値の参照月が変わる

- 根拠: [ForecastPipeline.swift:69](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:69)、[RiskAnalyzer.swift:63](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/RiskAnalyzer.swift:63)、[build_slp_table.py:42](/Users/mymac/zutsuu/tools/climatology/build_slp_table.py:42)。**静的確認・暦の月差を確認。**
- テーブルは西暦の季節月で作るが、参照は `Calendar.current.component(.month)`。イスラム暦・ヘブライ暦等では同じ日時の月番号が異なり、季節の違う平年分布で採点する。
- 修正方針: 平年値の月は指定タイムゾーンのグレゴリオ暦で計算する。表示用暦と分離する。受け入れ条件: 同日時・同地点・同タイムゾーンなら、端末の暦設定を変えても気圧スコアが変わらない。

### R22. Watchから受信した体調を公開ログに出している

- 根拠: [WatchSessionBridge.swift:44](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/WatchSessionBridge.swift:44)。**静的確認。**
- 体調の `feeling` と記録UUIDを明示的に `privacy: .public` で出している。ログの外部送信は確認していないが、診断ログを共有すると健康状態も含まれる。
- 修正方針: 保存成否だけを通常ログに残し、体調は除去またはprivate扱いにする。受け入れ条件: 通常の公開ログから体調と個別記録を読み取れない。

### R23. 「72時間」の通知説明と、実際の解析範囲が一致しない

- 根拠: [ForecastPipeline.swift:72](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/ForecastPipeline.swift:72)、[RiskAnalyzer.swift:60](/Users/mymac/zutsuu/ios/ZutsuuKit/Sources/RiskEngine/RiskAnalyzer.swift:60)、[TodayView.swift:127](/Users/mymac/zutsuu/ios/ZutsuuApp/Sources/TodayView.swift:127)。**静的確認。**
- 取得の終端を現在+72時間にし、解析は末尾6点を捨てるため、評価可能なのは概ね66時間先まで。「72時間以内に通知の予定はありません」「72時間分の通知が予約済み」という説明は残り約6時間を評価していない事実を隠す。
- 修正方針: 72時間を保証するなら前方窓のためさらに6時間を取得する。提供可能範囲が短い場合は評価済み終端を表示する。受け入れ条件: 67〜72時間先だけに上昇がある入力を正しく扱い、未評価を「予定なし」と表現しない。

## 追加で確認すべき事項・保守上の課題

以下は上記23件と分ける。実機・外部サービス検証が必要なものを、確定不具合として水増ししない。

- **バックグラウンド更新:** 毎回 `LocationProvider.current()` を呼び、失敗時の保存座標による取得がない。When In Use権限で実際にBG実行されたときの位置取得・失効・キャンセルを実機検証する。BGの実行頻度を前提に通知の継続を保証しない。
- **保存失敗後の再試行:** `CheckInStore.save` はinsert後のsave失敗でrollbackしない。次回fetchが未保存insertを見つけて正常returnしないか、ストレージ障害を注入して検証する。今回DBには触れていない。
- **再予約の競合:** `record()` と `refresh()` の再予約処理はawaitで交差しうる。新旧設定・学習結果・保留一覧の読み戻しを意図的に交差させ、古い結果が新しい予約を上書きしないか検証する。
- **Watch有効化後の再送:** activation完了は `refreshIfStale()` を呼ぶだけ。既に新しい予報があって送信のみ失敗したケースでは再送をスキップする。キャッシュを再送する経路を確認する。
- **入力の妥当性:** 空・欠時・非有限の予報をアプリの成功状態として公開しない契約が弱い。系列の等間隔性、現在を含むこと、最小範囲を入口で確認する。平年値binもmagic/サイズ以外のversion・次元を検証していない。
- **平年値の再生成:** `slp.*.nc` をすべて読むため、1991〜2020の全30年・欠測なし・正しい格子であることを確認しない。入力一覧・ハッシュ・生成環境を保存して再現可能にする。今回binの原データからの再構築はしていない。
- **LINE版の周辺:** ナウキャストのタイル番号と気象庁地域が東京固定。環境変数で他地点に変えた場合に対応しない。`buildRainForecast` も22時と翌02時の非連続な雨を「22〜3時」と結合することを再現した。HTTPにタイムアウトがなく、実行が長時間止まりうる。
- **リリース設定:** AdMobはテストID、SKAdNetworkは暫定リスト。Apple Weatherの `markURL` は取得のみで表示箇所がない。帰属表示・広告同意変更・プライバシー申告・Watchの不要な広告依存を、配布前に公式要件と照合する。
- **CI:** macOSの単体テストとアプリビルドはあるが、ForecastPipeline・NotificationClient・CheckInStore・Watch送受信・AdsCoordinatorの結合テストがない。TypeScriptにも時刻固定・HTTP失敗の自動テストがない。型チェックをCIへ追加する。
- **文書:** 指示が参照する `docs/playbooks/protocol.md` と `docs/prompts/commands.md` は存在しない。テスト件数、ファイル数、通知範囲、一部コメントが実装より古い。RiskEngine等には必須の4行ヘッダーがない。これらは挙動の修正より後で整理する。

## Claudeへの引き継ぎ

1. R01〜R04を先に扱う。特にR01・R02・R05・R08は通知の状態管理としてまとめて設計を確認し、それぞれの回帰ケースを残す。
2. 修正対象と関連ファイルを全文確認する。仕様が原因の箇所は実装と正典・既存テストを一緒に改め、「テストが通ったから正しい」で終わらせない。
3. 一時ハーネスの結果は上記の入力・期待値から再現できる。時刻・通知センター・保存・広告を差し替えられる小さな境界を作り、失敗と再実行をテストする。全面的な作り直しは不要。
4. DB変更・マイグレーションは禁止。必要な場合は提案のみ行う。`npm run build` も実行しない。（push 禁止は 2026-09-12 にユーザーが解除）
5. 既存のdebug/release単体テストに加え、修正した結合経路の検証結果を報告する。実機で未確認の項目はそのまま明記する。

維持したい点: 純粋なRiskEngineとOS入出力の分離、単位変換の集約、前方窓が欠ける末尾を返さない方針、記録IDの安定性、保存成功時だけ完了表示するUI、広告から健康データ型への依存を断つ構成、Reduce Motion対応と素材同梱テスト。これらを壊さず、状態の境界を補強する修正が適切。
