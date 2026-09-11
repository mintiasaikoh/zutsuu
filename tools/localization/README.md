<!-- /Users/mymac/zutsuu/tools/localization/README.md -->
<!-- String Catalog の再抽出手順。 -->
<!-- 文字列を足したときに、翻訳漏れを機械的に見つけられるようにするため。 -->
<!-- 関連: ../../docs/appcore-api.md §5, ../../ios/ZutsuuApp/project.yml -->
# String Catalog の再抽出

1. アプリをビルドする（`project.yml` で `SWIFT_EMIT_LOC_STRINGS: YES` 済み）。`.stringsdata` が DerivedData に出る
2. 各カタログへ流し込む（`--stringsdata` は複数の引数。zsh では `find … -print0 | xargs -0` で分ける）

```bash
DD=<DerivedData>/Build/Intermediates.noindex
T=$(xcrun --find xcstringstool)
sync() { find "$2" -name "*.stringsdata" -print0 | xargs -0 "$T" sync "$1" --stringsdata; }
sync ios/ZutsuuApp/Resources/Localizable.xcstrings            $DD/ZutsuuApp.build/Debug-iphonesimulator/ZutsuuApp.build
sync ios/ZutsuuWatch/Resources/Localizable.xcstrings          $DD/ZutsuuApp.build/Debug-watchsimulator/ZutsuuWatch.build
sync ios/ZutsuuWatchWidget/Resources/Localizable.xcstrings    $DD/ZutsuuApp.build/Debug-watchsimulator/ZutsuuWatchWidget.build
sync ios/ZutsuuKit/Sources/KiabouUI/Resources/Localizable.xcstrings $DD/ZutsuuKit.build/Debug-iphonesimulator/KiabouUI.build
sync ios/ZutsuuKit/Sources/AppCore/Resources/Localizable.xcstrings  $DD/ZutsuuKit.build/Debug-iphonesimulator/AppCore.build
```

3. 新しいキー（`localizations` が無い項目）に en / de / ko / zh-Hans を書く。`%lld / 18 pt` のような翻訳不要のキーは `shouldTranslate: false`
4. `xcodebuild` が通ることと、`-AppleLanguages "(en)"` で起動して日本語が残っていないことを確認する
