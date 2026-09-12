<!-- /Users/mymac/zutsuu/tools/climatology/README.md -->
<!-- 気圧平年値テーブルの再生成手順。 -->
<!-- 元データ・期間・形式を変えるときに、同じ手順で作り直せるようにするため。 -->
<!-- 関連: build_slp_table.py, show_points.py, ../../docs/research/2026-09-12-pressure-climatology.md -->
# 気圧平年値テーブルの生成

出力先: `ios/ZutsuuKit/Sources/AppCore/Resources/slp-climatology.bin`（約 740KB）。

```bash
python3 -m venv .venv && .venv/bin/pip install numpy netCDF4
mkdir -p slp && for y in $(seq 1991 2020); do
  curl -o slp/slp.$y.nc "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/Dailies/surface/slp.$y.nc"
done
.venv/bin/python build_slp_table.py slp ../../ios/ZutsuuKit/Sources/AppCore/Resources/slp-climatology.bin
.venv/bin/python show_points.py ../../ios/ZutsuuKit/Sources/AppCore/Resources/slp-climatology.bin
```

- 元データは NOAA PSL の NCEP/NCAR Reanalysis 1（パブリックドメイン）。年 1 ファイル約 6MB、30 年で約 190MB
- 期間・統計量・格子を変えたら `ReanalysisClimatology.swift` の定数とテストの期待値も合わせる
- 生成した `.bin` と `show_points.py` の出力の一部（代表地点）を調査ノートに残す
- 生成すると `manifest.json`（入力 30 ファイルの sha256、年の連続性、出力の sha256、生成環境）が同じディレクトリに出る。
  同梱の `.bin` の sha256 と `manifest.json` の `output_sha256` が一致することが再現性の確認になる（2026-09-12 に一致を確認）
