"""Side-silhouette IoU: our Model Y (temp/modely/prev/StealthGrey_left.png from build.py final) vs the owner's-manual drawing.

    uv run --no-project --with pillow --with numpy python scripts/blender/modely/outline_iou.py

Manual: tripo-refs collections/特斯拉/車款/Model_Y/official/manual__dimensions.png (RGBA, transparent background).
Both silhouettes are column envelopes of alpha > 127 (per column, top-most to bottom-most opaque pixel: roof line
down to sill or tire bottom), scaled to the same length, aligned at the front and the ground line.
Acceptance (references/models.md): IoU >= 0.90.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[3]
MANUAL = Path("D:/github/tripo-refs/collections/特斯拉/車款/Model_Y/official/manual__dimensions.png")
OURS = REPO / "temp/modely/prev/StealthGrey_left.png"
CROP = (272, 2, 762, 171)   # side view (tires end at y 170, ground line y 176); G arrow at x 520-545, y >= 158


def envelope(drawn):
    out = np.zeros_like(drawn)
    for x in range(drawn.shape[1]):
        ys = np.nonzero(drawn[:, x])[0]
        if len(ys) > 1:
            out[ys[0]:ys[-1] + 1, x] = True
    return out


def manual_mask():
    a = np.asarray(Image.open(MANUAL).convert("RGBA").crop(CROP))[..., 3] > 127
    a[156:, 520 - CROP[0]:546 - CROP[0]] = False   # the "G" ground-clearance arrow
    return envelope(a)


def ours_mask():
    return envelope(np.asarray(Image.open(OURS).convert("RGBA"))[..., 3] > 127)


def norm(m, w=800):
    ys, xs = np.nonzero(m)
    m = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h = round(m.shape[0] * w / m.shape[1])
    return np.asarray(Image.fromarray(m.astype(np.uint8) * 255).resize((w, h), Image.NEAREST)) > 127


def main():
    a, b = norm(manual_mask()), norm(ours_mask())
    ratio = f"height/length manual {a.shape[0] / a.shape[1]:.4f} ours {b.shape[0] / b.shape[1]:.4f}"
    h = max(a.shape[0], b.shape[0])
    pad = lambda m: np.vstack([np.zeros((h - m.shape[0], m.shape[1]), bool), m])   # align the ground line
    a, b = pad(a), pad(b)
    iou = (a & b).sum() / (a | b).sum()
    print(f"{ratio}  IoU {iou:.3f}")
    out = np.zeros(a.shape + (3,), np.uint8)
    out[a & b], out[a & ~b], out[~a & b] = (200, 200, 200), (255, 60, 60), (60, 120, 255)
    Image.fromarray(out).save(REPO / "temp/modely/prev/outline_iou.png")
    return 0 if iou >= 0.90 else 1


if __name__ == "__main__":
    sys.exit(main())
