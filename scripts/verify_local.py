# -*- coding: utf-8 -*-
"""Tesla 專屬的靜態檢查：scripts/verify_mod.py 第 19 項會呼叫；單獨跑 `python scripts/verify_local.py`。

坐姿片段與 AnimSet 節點是 scripts/seat_anim.py 生成的（每台的坐姿片段、idle／aim 節點、原版全身 actions 節點的坐姿版）：
手改產出、改了 cars/<車>.py 沒重產生、遊戲更新改了原版 actions 節點，`seat_anim.py --check` 都會不過。
"""
import subprocess
import sys
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
p = subprocess.run(["uv", "run", "--quiet", "scripts/seat_anim.py", "--check"], cwd=REPO, capture_output=True, text=True,
                   encoding="utf-8", errors="replace")
print(("坐姿片段與節點是最新：" if p.returncode == 0 else "坐姿片段或節點跟生成器不符：") + (p.stdout + p.stderr).strip())
sys.exit(p.returncode)
