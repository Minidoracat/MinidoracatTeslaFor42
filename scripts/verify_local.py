# -*- coding: utf-8 -*-
"""Tesla 專屬的靜態檢查：scripts/verify_mod.py 第 19 項會呼叫；單獨跑 `python scripts/verify_local.py`。

坐姿片段與 AnimSet 節點是 scripts/seat_anim.py 生成的（每台的坐姿片段、idle／aim 節點、原版全身 actions 節點的坐姿版）：
手改產出、改了 cars/<車>.py 沒重產生、遊戲更新改了原版 actions 節點，`seat_anim.py --check` 都會不過。
車身 skin 的四個角：scripts/skin_check.py（訊息由它自己印）。
TallHats.lua（坐著時要藏的高帽子）是 seat_head.py --tall-lua 量出來的：scripts/tall_hats.py 比對它檔頭記的各車輸入雜湊
（FBX、車輛腳本、坐姿片段、量測程式），改了車殼或坐姿沒重產就不過。2026-11-18 前沒有這一關，五台車的列過期都沒人發現。
升級件（防護件、車用冰箱）的零件與物品契約：scripts/upgrades_check.py（逐條見它的檔頭）。
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
tall, tall_out = run("scripts/tall_hats.py")
upg, upg_out = run("scripts/upgrades_check.py")
print(("坐姿片段與節點是最新：" if seat == 0 else "坐姿片段或節點跟生成器不符：") + seat_out + "；" + skin_out + "；" + tall_out + "；" + upg_out)
sys.exit(seat or skin or tall or upg)
