# /// script
# dependencies = ["pillow"]
# ///
# -*- coding: utf-8 -*-
"""車身 skin 的四個角要是 pzveh.CABIN_UV0_RGB（scripts/verify_local.py 會呼叫）。

車內的面 UV0 都在 (0, 0)，Viewpoint 用 skin 那一格的顏色畫整個車內（pzveh.cabin_corners）。convert.py 的 UV_FILL
曾把車內的面當成沒烘到的細三角形，用深色填掉 (0, 0) 那個角，cabin_corners 看到不是黑的就不塗：Model 3、Model Y L、
Model S、Cybertruck 的那一格變成 (10–27, …)，離線出圖與車外實機圖都看不出來（2026-11-13）。
"""
import glob
import os
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WANT = (52, 52, 56)     # pzveh.CABIN_UV0_RGB
SKIP = ("_mask.png", "_lights.png", "_wheel.png", "_wheelrear.png", "MinidoracatTesla_Detail.png")
bad, n = [], 0
for p in sorted(glob.glob(os.path.join(REPO, "MOD", "**", "textures", "Vehicles", "MinidoracatTesla_*.png"), recursive=True)):
    if p.endswith(SKIP):
        continue
    im = Image.open(p).convert("RGB")
    w, h = im.size
    got = [im.getpixel(xy) for xy in ((1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2))]
    n += 1
    if any(g != WANT for g in got):
        bad.append(f"{os.path.basename(p)}: 四角 {got}")
print(f"車身 skin 四角是 {WANT}（{n} 張）" if not bad else "車身 skin 的角不是 CABIN_UV0_RGB：" + "；".join(bad[:6])
      + (f"…共 {len(bad)} 張" if len(bad) > 6 else ""))
sys.exit(1 if bad else 0)
