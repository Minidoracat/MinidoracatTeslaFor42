# -*- coding: utf-8 -*-
"""Tesla 專屬的靜態檢查：scripts/verify_mod.py 第 19 項會呼叫；單獨跑 `python scripts/verify_local.py`。

坐姿片段與 AnimSet 節點是 scripts/seat_anim.py 生成的（每台的坐姿片段、idle／aim 節點、原版全身 actions 節點的坐姿版）：
手改產出、改了 cars/<車>.py 沒重產生、遊戲更新改了原版 actions 節點，`seat_anim.py --check` 都會不過。
車身 skin 的四個角：scripts/skin_check.py（訊息由它自己印）。
"""
import subprocess
import sys
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(script, *args):
    p = subprocess.run(["uv", "run", "--quiet", script, *args], cwd=REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout + p.stderr).strip()


seat, seat_out = run("scripts/seat_anim.py", "--check")
skin, skin_out = run("scripts/skin_check.py")
print(("坐姿片段與節點是最新：" if seat == 0 else "坐姿片段或節點跟生成器不符：") + seat_out + "；" + skin_out)
sys.exit(seat or skin)
