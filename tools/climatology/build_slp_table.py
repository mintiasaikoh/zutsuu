#!/usr/bin/env python3
# /Users/mymac/zutsuu/tools/climatology/build_slp_table.py
# NCEP/NCAR Reanalysis 1 の日平均海面気圧から、格子・月ごとの 10/25/40 パーセンタイル表を作る。
# 絶対気圧スコア（riskengine-api.md §3.2）が使う 3 つの境界だけを同梱し、1MB 未満に収めるため。
# 関連: docs/research/2026-09-12-pressure-climatology.md, ios/ZutsuuKit/Sources/AppCore/ReanalysisClimatology.swift
"""
使い方:
  python build_slp_table.py <slp.YYYY.nc を置いたディレクトリ> <出力 .bin>

入力: https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis/Dailies/surface/slp.YYYY.nc（1991〜2020）
出力: ヘッダ 16 byte + Int16 little-endian の配列 [month(12)][lat(73)][lon(144)][p10, p25, p40]（hPa × 10）
ヘッダ: magic "ZSLP", version u16 = 1, lat 数 u16, lon 数 u16, 月数 u16, 統計量数 u16, 予約 2 byte
格子: lat は +90 から -90 へ 2.5° 刻み（元データの順）、lon は 0 から 357.5 へ 2.5° 刻み
"""
import glob
import struct
import sys

import numpy as np
from netCDF4 import Dataset

PERCENTILES = (10, 25, 40)


def load(directory):
    months, values = [], []
    lat = lon = None
    for path in sorted(glob.glob(f"{directory}/slp.*.nc")):
        with Dataset(path) as ds:
            slp = np.asarray(ds.variables["slp"][:], dtype=np.float64)  # (time, lat, lon) in Pa or mb
            units = getattr(ds.variables["slp"], "units", "")
            if units.lower().startswith("pa"):
                slp = slp / 100.0
            time = ds.variables["time"]
            from netCDF4 import num2date
            dates = num2date(time[:], time.units, getattr(time, "calendar", "standard"))
            if lat is None:
                lat = np.asarray(ds.variables["lat"][:])
                lon = np.asarray(ds.variables["lon"][:])
            months.append(np.array([d.month for d in dates], dtype=np.int16))
            values.append(slp)
    return lat, lon, np.concatenate(months), np.concatenate(values)


def build(lat, lon, months, values):
    table = np.zeros((12, len(lat), len(lon), len(PERCENTILES)), dtype=np.int16)
    for m in range(1, 13):
        sample = values[months == m]
        q = np.percentile(sample, PERCENTILES, axis=0)  # (3, lat, lon)
        table[m - 1] = np.rint(np.moveaxis(q, 0, -1) * 10).astype(np.int16)
    return table


def main():
    directory, output = sys.argv[1], sys.argv[2]
    lat, lon, months, values = load(directory)
    assert len(lat) == 73 and len(lon) == 144, (len(lat), len(lon))
    assert lat[0] == 90 and lat[-1] == -90 and lon[0] == 0
    table = build(lat, lon, months, values)
    header = struct.pack("<4sHHHHH2x", b"ZSLP", 1, len(lat), len(lon), 12, len(PERCENTILES))
    with open(output, "wb") as f:
        f.write(header)
        f.write(table.astype("<i2").tobytes())
    print(f"days={len(months)} table={table.shape} bytes={16 + table.size * 2}")


if __name__ == "__main__":
    main()
