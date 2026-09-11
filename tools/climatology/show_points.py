#!/usr/bin/env python3
# /Users/mymac/zutsuu/tools/climatology/show_points.py
# 生成したテーブルから代表地点の月別境界値を表示する。
# Swift 側のテストの期待値と、調査ノートの「読み」を同じ数値から書くため。
# 関連: build_slp_table.py
import struct
import sys

import numpy as np

path = sys.argv[1]
with open(path, "rb") as f:
    magic, version, nlat, nlon, nmonth, nstat = struct.unpack("<4sHHHHH2x", f.read(16))
    table = np.frombuffer(f.read(), dtype="<i2").reshape(nmonth, nlat, nlon, nstat)
assert magic == b"ZSLP"

points = {"Tokyo": (35.68, 139.77), "Reykjavik": (64.13, -21.9), "Ulaanbaatar": (47.92, 106.92),
          "Singapore": (1.35, 103.82), "Mexico City": (19.43, -99.13), "Sydney": (-33.87, 151.21)}
for name, (la, lo) in points.items():
    i = int(round((90 - la) / 2.5))
    j = int(round((lo % 360) / 2.5)) % nlon
    for m in (1, 7):
        p = table[m - 1, i, j] / 10
        print(f"{name:12s} m{m:02d} p10={p[0]:.1f} p25={p[1]:.1f} p40={p[2]:.1f}")
