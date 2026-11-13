# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
"""兩版外觀截圖對照：同框檢查、每色每向差異表、對照圖（收斂 temp/fit-1112/game 底下每輪重寫的 m8.py／make_cmp*.py）。

    uv run scripts/e2e_look.py <before> <after> [--match=REGEX] [--thr 30] [--box x0,y0,x1,y1] [--skip edges-sp|x0,y0,x1,y1 ...] [--out DIR]
    uv run scripts/e2e_look.py --self-test

輸入（兩邊各一個目錄，遞迴找名叫 Screenshots 的目錄，不限深度）：
  - regress.py 的 --out 目錄（例：regress.py --mod MinidoracatTeslaFor42 look-mx --out temp/look-a）：
    <目錄>/<案名>/<輪次 id>/{Screenshots|client1/Screenshots}/*.png，輪次目錄有 manifest.json、result.json
  - 單輪 collect：<目錄>/{Screenshots|client1/Screenshots}/*.png
  兩版的圖用（案名, 檔名）配對；案名＝目錄到輪次目錄之間的路徑（輪次 id 每輪不同，不算進去），單輪 collect 沒有案名。
  車款、色名取輪次 manifest.json 的 args.defines 的 car／paint；方向取檔名裡的 N／NE／…／NW 段（edges-SE-shut.png → SE）。
量法（after-2f13872/mx/RESULT.txt 第 0、4 項）：
  - 同框：路面亮度＝[700:800, 200:400] 平均；草地飽和度＝色相 60–180°、S>30、V>30 的像素 S 中位數（不到 500 px 記 nan，
    例：N 向）。兩版差 >ROAD_TOL 或 >GRASS_TOL 記「環境不同，不能比」（GameMX8 白輪去飽和中途在變：草地 185→172…146）。
  - 差異：三通道 |差| 最大值 >--thr 的像素數與占 --box（預設整張）的比例；「±1px」＝每個像素對另一張 ±1 px 內最接近的
    像素的差，兩個方向取大（整台車次像素位移、輪輻相位這類差會在這欄消失）。
  - --skip 的框不量（對照圖上壓暗）。家族 modely-edges-sp 不帶 --define clean=1 時，畫面裡有站在車西北 2 格的角色（每輪外觀
    隨機）和右上的 moodle 圖示，兩輪必有差：比那種圖加 --skip edges-sp（SKIP_EDGES_SP，也蓋掉 SE／S 向車頂一小塊）。
    regress.json 的 look 群組都帶 clean=1（E2EKit.lockLook 每 tick 藏介面、角色 alpha 0），temp/ 的一次性 *-edges-clean-sp 也是，不用加。
輸出（--out，預設 temp/e2e-look/<before 名>--<after 名>）：look.md（同 stdout 的表）、cmp-<案名>-<n>.png 對照圖
（每列 before｜after｜差異疊色：洋紅＝|差|>thr 但容 1 px 後沒了，紅＝容 1 px 後仍 >thr；只放有差或不同框的圖，每張 8 列、寬 ≤3000）。
結束碼：0＝全部同框且讀得到；1＝有不同框、讀不到、尺寸不同、只有一邊有、或同一（案名, 檔名）有兩張；2＝參數錯或沒有可配對的圖。
"""
import argparse
import json
import os
import re
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
ROAD = (slice(700, 800), slice(200, 400))   # 路面（modely-edges-sp 一車一向、鏡頭跟著站位，路面固定在這格）
ROAD_TOL, GRASS_TOL = 1.0, 3.0              # 同框兩輪實測：路面差 ≤0.4、草地 ≤1（after-2f13872/mx/light.txt）
MAXW, ROWS, GAP = 3000, 8, 10
# modely-edges-sp：角色（x 905–995、y 410–650）、右上 moodle 圖示欄（1862–1909, 120–198，留到第 3 格）；
# 量自 GameCT3 tesla-gct3-blk-main 對 -blk-r5／-blk-r6、ss-main 對 ss-r6 八向
SKIP_EDGES_SP = ((900, 400, 1010, 655), (1855, 110, 1915, 260))


def load(p):
    with Image.open(p) as im:
        return np.asarray(im.convert("RGB"), dtype=np.int16)


def env(a):
    road = float(a[ROAD].mean()) if a.shape[0] >= 800 and a.shape[1] >= 400 else float("nan")
    hsv = np.asarray(Image.fromarray(a.astype(np.uint8)).convert("HSV"), dtype=np.int16)
    g = (hsv[..., 0] >= 43) & (hsv[..., 0] <= 127) & (hsv[..., 1] > 30) & (hsv[..., 2] > 30)  # PIL 色相 0–255：60–180°
    return road, (float(np.median(hsv[..., 1][g])) if g.sum() > 500 else float("nan"))


def same_frame(ea, eb):
    def close(x, y, tol):
        return (np.isnan(x) and np.isnan(y)) or abs(x - y) <= tol
    return close(ea[0], eb[0], ROAD_TOL) and close(ea[1], eb[1], GRASS_TOL)


def tol1(a, b):
    """容 1 px 位移的差：a 的每個像素對 b 在 ±1 px 內最接近的那個像素的差（三通道最大），兩個方向取大的（m8.tol）。"""
    def one(p, q):
        best = None
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                d = np.abs(p - np.roll(q, (dy, dx), (0, 1))).max(2)
                best = d if best is None else np.minimum(best, d)
        return best
    return np.maximum(one(a, b), one(b, a))


def run_meta(shots):
    """Screenshots 目錄 → (輪次目錄, defines)。Screenshots 在 clientN／server 底下時輪次目錄再上一層。"""
    rd = os.path.dirname(shots)
    if re.fullmatch(r"client\d+|server", os.path.basename(rd)):
        rd = os.path.dirname(rd)
    try:
        with open(os.path.join(rd, "manifest.json"), encoding="utf-8") as fh:
            man = json.load(fh)
    except (OSError, ValueError):
        return rd, {}
    defs = (man.get("args") or {}).get("defines")
    if defs is None:   # 較早的 manifest 沒有 args：從 argv 撿 --define
        argv = man.get("argv") or []
        defs = dict(argv[i + 1].split("=", 1) for i, x in enumerate(argv[:-1]) if x == "--define" and "=" in argv[i + 1])
    return rd, defs


def scan(root, match):
    """root 底下的截圖 → ({(案名, 檔名): 路徑}, {案名: defines}, 重複清單)。"""
    shots, meta, dup = {}, {}, []
    root = os.path.abspath(root)
    for d, subs, files in os.walk(root):
        if os.path.basename(d) != "Screenshots":
            continue
        rd, defs = run_meta(d)
        has_id = any(os.path.isfile(os.path.join(rd, f)) for f in ("manifest.json", "result.json", "run.json"))
        case = "" if os.path.samefile(rd, root) else os.path.relpath(os.path.dirname(rd) if has_id else rd, root)
        case = "" if case == "." else case.replace("\\", "/")
        meta.setdefault(case, defs)
        for f in sorted(files):
            if f.lower().endswith(".png") and (not match or re.search(match, f)):
                k = (case, f)
                if k in shots:
                    dup.append(f"{case or '.'}/{f}：{shots[k]} 與 {os.path.join(d, f)}")
                shots[k] = os.path.join(d, f)
    return shots, meta, dup


def direction(f):
    return next((t for t in os.path.splitext(f)[0].split("-") if t in DIRS), "")


def order(k):
    d = direction(k[1])
    return k[0], DIRS.index(d) if d else 99, k[1]


def compare(a, b, thr, box=None, skip=()):
    if a.shape != b.shape:
        raise ValueError(f"尺寸不同 {a.shape[1]}x{a.shape[0]} / {b.shape[1]}x{b.shape[0]}")
    x0, y0, x1, y1 = box or (0, 0, a.shape[1], a.shape[0])
    keep = np.zeros(a.shape[:2], bool)
    keep[y0:y1, x0:x1] = True
    for sx0, sy0, sx1, sy1 in skip:
        keep[sy0:sy1, sx0:sx1] = False
    hot = (np.abs(a - b).max(2) > thr) & keep
    n = int(hot.sum())
    kept = (tol1(a, b) > thr) & keep if n else hot   # ±1px 的差 ≤ 原差：原差沒有就不必算
    return {"a": a, "b": b, "keep": keep, "hot": hot, "kept": kept, "n": n, "n1": int(kept.sum()),
            "pct": 100 * n / max(1, int(keep.sum())), "ea": env(a), "eb": env(b), "box": (x0, y0, x1, y1)}


def crop_of(r):
    x0, y0, x1, y1 = r["box"]
    ys, xs = np.nonzero(r["kept"] if r["n1"] else r["hot"])
    if not len(xs):
        return x0, y0, x1, y1
    cx0, cy0, cx1, cy1 = xs.min() - 40, ys.min() - 40, xs.max() + 41, ys.max() + 41
    w, h = min(x1 - x0, max(200, cx1 - cx0)), min(y1 - y0, max(150, cy1 - cy0))
    cx0, cy0 = max(x0, min((cx0 + cx1 - w) // 2, x1 - w)), max(y0, min((cy0 + cy1 - h) // 2, y1 - h))
    return cx0, cy0, cx0 + w, cy0 + h


def panels(r):
    c = crop_of(r)
    sl = (slice(c[1], c[3]), slice(c[0], c[2]))
    a, b = r["a"][sl].astype(np.uint8), r["b"][sl].astype(np.uint8)
    over = np.repeat((b.mean(2, keepdims=True) * 0.5 + 40).astype(np.uint8), 3, 2)
    over[~r["keep"][sl]] //= 3   # --skip 的框壓暗
    hot, kept = r["hot"][sl], r["kept"][sl]
    w = c[2] - c[0]
    s = (MAXW - 4 * GAP) / (3 * w)
    if s < 1:   # 縮小前把標記擴開，1 px 的差縮完還看得到
        k = 2 * int(np.ceil(1 / s)) + 1
        hot = np.asarray(Image.fromarray(hot.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(k))) > 0
        kept = np.asarray(Image.fromarray(kept.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(k))) > 0
    over[hot] = (255, 0, 255)
    over[kept] = (255, 0, 0)
    ims = [Image.fromarray(x) for x in (a, b, over)]
    if s >= 1:
        s = min(4, int(s))
        return [im.resize((im.width * s, im.height * s), Image.NEAREST) for im in ims], c, s
    return [im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS) for im in ims], c, s


def font():
    try:
        return ImageFont.load_default(18)
    except TypeError:   # Pillow < 10.1
        return ImageFont.load_default()


def sheet(rows, out, head):
    """rows＝[(標題, [圖, 圖, 圖])]；圖上文字只用英文與數字。"""
    f = font()
    W = min(MAXW, max(sum(i.width for i in ims) + GAP * (len(ims) + 1) for _, ims in rows))
    H = 34 + sum(max(i.height for i in ims) + 34 for _, ims in rows) + GAP
    im = Image.new("RGB", (W, H), (255, 255, 255))
    dr = ImageDraw.Draw(im)
    dr.text((GAP, 6), head, fill=(0, 0, 0), font=f)
    y = 34
    for title, ims in rows:
        dr.text((GAP, y + 4), title, fill=(0, 0, 0), font=f)
        y, x = y + 28, GAP
        for i in ims:
            im.paste(i, (x, y))
            x += i.width + GAP
        y += max(i.height for i in ims) + 6
    im.save(out)
    return im.size


def ascii_(s):
    return s.encode("ascii", "replace").decode()


def rect(s):
    if s == "edges-sp":
        return list(SKIP_EDGES_SP)
    try:
        v = tuple(int(x) for x in s.split(","))
    except ValueError:
        v = ()
    if len(v) != 4 or v[0] >= v[2] or v[1] >= v[3]:
        raise argparse.ArgumentTypeError(f"{s!r}：要 x0,y0,x1,y1 且 x0<x1、y0<y1")
    return [v]


def main(argv=None):
    ap = argparse.ArgumentParser(description="兩版外觀截圖對照（見檔頭）")
    ap.add_argument("before", nargs="?")
    ap.add_argument("after", nargs="?")
    ap.add_argument("--match", help="只比檔名符合這個 regex 的圖（例：--match=-shut；開頭是 - 要用 = 連著寫）")
    ap.add_argument("--thr", type=int, default=30, help="三通道 |差| 最大值的門檻（預設 30）")
    ap.add_argument("--box", type=rect, help="只量這個框 x0,y0,x1,y1（預設整張）")
    ap.add_argument("--skip", type=rect, action="extend", default=[],
                    help="不量的框 x0,y0,x1,y1，可重複；edges-sp＝modely-edges-sp 的角色與右上圖示（見檔頭）")
    ap.add_argument("--out", help="輸出目錄（預設 temp/e2e-look/<before 名>--<after 名>）")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args(argv)
    if a.self_test:
        return self_test()
    if not (a.before and a.after):
        ap.print_usage()
        return 2
    box = a.box[0] if a.box else None
    (sa, ma, da), (sb, mb, db) = scan(a.before, a.match), scan(a.after, a.match)
    keys = sorted(set(sa) & set(sb), key=order)
    if not keys:
        print(f"沒有可配對的截圖：before {len(sa)} 張、after {len(sb)} 張（配對鍵＝案名＋檔名）")
        return 2
    out = a.out or os.path.join("temp", "e2e-look", f"{os.path.basename(os.path.abspath(a.before))}--{os.path.basename(os.path.abspath(a.after))}")
    os.makedirs(out, exist_ok=True)
    thr = a.thr
    lines = [f"# 外觀對照 before={os.path.abspath(a.before)} after={os.path.abspath(a.after)}",
             f"門檻 |差|>{thr}；範圍 {'box ' + ','.join(map(str, box)) if box else '整張'}"
             + (f"，不量 {' '.join(','.join(map(str, s)) for s in a.skip)}" if a.skip else "")
             + f"；同框＝路面差 ≤{ROAD_TOL}、草地飽和度差 ≤{GRASS_TOL}", "",
             f"| 案名 | 車款 | 色 | 向 | 檔名 | 路面 b→a | 草地 b→a | 同框 | >{thr} px | % | ±1px px |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    print("\n".join(lines))
    bad, sheets, rows, last = [], [], [], None

    def flush(case):
        for i in range(0, len(rows), ROWS):
            p = os.path.join(out, f"cmp-{re.sub(r'[^A-Za-z0-9._-]+', '_', case) or 'run'}-{i // ROWS + 1}.png")
            sheets.append((p, sheet(rows[i:i + ROWS], p, f"before {ascii_(os.path.basename(os.path.abspath(a.before)))} | after "
                                    f"{ascii_(os.path.basename(os.path.abspath(a.after)))} | overlay: magenta diff>{thr} gone with 1px shift, red diff>{thr} after 1px shift")))
        rows.clear()

    for k in keys:
        case, f = k
        if case != last and last is not None:
            flush(last)
        last = case
        defs = mb.get(case) or ma.get(case) or {}
        car, paint, d = defs.get("car", "").replace("MinidoracatTesla_", ""), defs.get("paint", ""), direction(f)
        try:
            r = compare(load(sa[k]), load(sb[k]), thr, box, a.skip)
        except (OSError, ValueError) as e:
            bad.append(f"讀不到或不能比：{case or '.'}/{f}：{e}")
            row = f"| {case} | {car} | {paint} | {d} | {f} | — | — | 讀不到 | — | — | — |"
            lines.append(row); print(row)
            continue
        ok = same_frame(r["ea"], r["eb"])
        if not ok:
            bad.append(f"環境不同，不能比：{case or '.'}/{f}（路面 {r['ea'][0]:.1f}→{r['eb'][0]:.1f}、草地 {r['ea'][1]:.0f}→{r['eb'][1]:.0f}）")
        row = (f"| {case} | {car} | {paint} | {d} | {f} | {r['ea'][0]:.1f}→{r['eb'][0]:.1f} | {r['ea'][1]:.0f}→{r['eb'][1]:.0f} | "
               f"{'是' if ok else '環境不同，不能比'} | {r['n']} | {r['pct']:.3f} | {r['n1']} |")
        lines.append(row); print(row)
        if r["n"] or not ok:
            ims, c, s = panels(r)
            rows.append((ascii_(f"{case} {car} {paint} {d} {f}  >{thr}: {r['n']} px ({r['pct']:.3f}%)  +-1px: {r['n1']} px  "
                                f"crop {c[0]},{c[1]}-{c[2]},{c[3]} x{s:g}" + ("" if ok else "  ENV DIFF: not comparable")), ims))
    flush(last)
    only = [f"只有 before 有：{c or '.'}/{f}" for c, f in sorted(set(sa) - set(sb), key=order)]
    only += [f"只有 after 有：{c or '.'}/{f}" for c, f in sorted(set(sb) - set(sa), key=order)]
    bad += [f"同一（案名, 檔名）有兩張，指到單輪或 regress 的 --out 目錄：{x}" for x in da + db] + only
    lines += ["", f"對照圖（只放有差或不同框的圖）：{len(sheets)} 張"] + [f"- {os.path.abspath(p)} {w}x{h}" for p, (w, h) in sheets]
    lines += ["", f"問題 {len(bad)} 項" + ("（結束碼 1）：" if bad else "：無")] + [f"- {x}" for x in bad]
    print("\n".join(lines[-(len(sheets) + len(bad) + 4):]))
    with open(os.path.join(out, "look.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"表：{os.path.abspath(os.path.join(out, 'look.md'))}")
    return 1 if bad else 0


def self_test():
    # 1. 差異計數與容 1 px：左半 20、右半 200；after 整張右移 1 px（邊界那欄＋np.roll 繞回的第 0 欄各 60 px）再改 3 點
    a = np.zeros((60, 80, 3), np.int16)
    a[:, 40:] = 200
    b = np.roll(a, 1, axis=1)
    for y, x, v in ((10, 10, 120), (30, 20, 120), (50, 70, 100)):
        b[y, x] = v
    r = compare(a, b, 30, None)
    assert (r["n"], r["n1"]) == (123, 3), (r["n"], r["n1"])
    # 2. 同框：草地去飽和要抓到，同一張要過
    g = np.zeros((1080, 1920, 3), np.int16)
    g[...] = (60, 160, 60)
    g[ROAD] = 100
    pale = g.copy()
    pale[..., 0], pale[..., 2] = 100, 100
    assert same_frame(env(g), env(g)) and not same_frame(env(g), env(pale)), (env(g), env(pale))
    # 3. 整套：before 是 regress 形狀（Screenshots 在輪次目錄下）、after 是 client1/Screenshots；一張同框有差、一張環境不同
    os.makedirs(os.path.join(REPO, "temp"), exist_ok=True)
    with tempfile.TemporaryDirectory(dir=os.path.join(REPO, "temp")) as tmp:
        man = {"args": {"defines": {"car": "MinidoracatTesla_ModelX", "paint": "PearlWhite"}}}
        for side, sub in (("bef", "Screenshots"), ("aft", os.path.join("client1", "Screenshots"))):
            rd = os.path.join(tmp, side, "look-mx-white", f"rid-{side}")
            os.makedirs(os.path.join(rd, sub))
            with open(os.path.join(rd, "manifest.json"), "w", encoding="utf-8") as fh:
                json.dump(man, fh)
            ch = g.copy()
            if side == "aft":
                ch[500:505, 900:910] = 255
            Image.fromarray(ch.astype(np.uint8)).save(os.path.join(rd, sub, "edges-SE-shut.png"))
            Image.fromarray((g if side == "bef" else pale).astype(np.uint8)).save(os.path.join(rd, sub, "edges-W-shut.png"))
        rc = main([os.path.join(tmp, "bef"), os.path.join(tmp, "aft"), "--out", os.path.join(tmp, "out")])
        md = open(os.path.join(tmp, "out", "look.md"), encoding="utf-8").read()
        assert rc == 1 and "| look-mx-white | ModelX | PearlWhite | SE | edges-SE-shut.png |" in md and "| 是 | 50 |" in md, md
        assert "環境不同，不能比" in md.split("edges-W-shut.png")[1], md
        png = os.path.join(tmp, "out", "cmp-look-mx-white-1.png")
        with Image.open(png) as im:
            assert im.width <= MAXW, im.size
        rc = main([os.path.join(tmp, "bef"), os.path.join(tmp, "aft"), "--match=-SE-", "--out", os.path.join(tmp, "out2")])
        assert rc == 0, rc
    print("e2e_look self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
