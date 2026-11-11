"""Side-view silhouette IoU of a source OBJ against an official design-studio SIDE render (prep_model_yl.py's check).
The render (1920 x 1080, transparent; about 4.31 mm/px, the nose at x 401, the ground on row 703: temp/plan-yl-1111
specs.md section 3): the car is its alpha >= 250 (the shadow under it is 129-249). The OBJ (front -X, Y up, metres)
is projected along its width, its nose and its lowest point (the tyres) on the calibration's nose column and ground row,
the licence plates (Object_11/12: the build drops them, the renders have none) left out. Both silhouettes are filled
(the render's see-through windows, the gaps in the source's wheels).
    uv run --no-project --with pillow --with numpy python scripts/blender/skf/side_iou.py <obj> <render.png> [out.png]
        [--fit]   # fit the calibration (on the untouched source against its own car's render: the render is a
                  # perspective camera, so its scale differs a little along x and y)
        [--cal=sx,sy,x0,r0]   # px per metre along the length / height, nose column, ground row
Prints the IoU (and the fitted calibration); out.png: red = render only, blue = OBJ only, grey = both.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw

SKIP = ("Object_11", "Object_12")


def load_obj(path):
    """(vertices N x 3, triangles M x 3) of the OBJ, SKIP objects' faces left out."""
    vs, tri, skip = [], [], False
    with open(path) as f:
        for line in f:
            t = line[:2]
            if t == "v ":
                vs.append(line[2:].split()[:3])
            elif t == "f ":
                if not skip:
                    ids = [int(w.split("/")[0]) for w in line[2:].split()]
                    tri += [(ids[0], ids[k], ids[k + 1]) for k in range(1, len(ids) - 1)]
            elif t == "o ":
                skip = line[2:].strip().startswith(SKIP)
    v = np.array(vs, float)
    t = np.array(tri, np.int64)
    return v, np.where(t < 0, t + len(v), t - 1)


def filled(a):
    """a with its holes (pixels not reached from the corner) filled."""
    out = Image.fromarray((~a).astype(np.uint8) * 255).convert("RGB")   # (Pillow 13's floodfill left an "L" unchanged)
    ImageDraw.floodfill(out, (0, 0), (128, 0, 0))
    return np.array(out)[..., 0] != 128


def official(path):
    return filled(np.array(Image.open(path).convert("RGBA"))[..., 3] >= 250)


def raster(v, t, cal, shape):
    sx, sy, x0, r0 = cal
    keep = np.unique(t)
    x = x0 + (v[:, 0] - v[keep, 0].min()) * sx
    y = r0 - (v[:, 1] - v[keep, 1].min()) * sy
    img = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(img)
    for a, b, c in t:
        d.polygon([(x[a], y[a]), (x[b], y[b]), (x[c], y[c])], fill=255)
    return filled(np.array(img) > 0)


def iou(a, b):
    return (a & b).sum() / (a | b).sum()


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    obj, ref = args[:2]
    cal = (1000 / 4.31, 1000 / 4.31, 401.0, 703.0)
    for f in flags:
        if f.startswith("--cal="):
            cal = tuple(float(c) for c in f.split("=", 1)[1].split(","))
    v, t = load_obj(obj)
    want = official(ref)
    if "--fit" in flags:                                   # coordinate descent, px steps then sub-px
        best = iou(raster(v, t, cal, want.shape), want)
        for step in (np.array((2.0, 2.0, 1.0, 1.0)), np.array((0.5, 0.5, 0.25, 0.25))):
            moved = True
            while moved:
                moved = False
                for k in range(4):
                    for sg in (-1, 1):
                        c = np.array(cal)
                        c[k] += sg * step[k]
                        q = iou(raster(v, t, c, want.shape), want)
                        if q > best:
                            best, cal, moved = q, tuple(c), True
        print("FIT --cal=%.2f,%.2f,%.2f,%.2f" % cal)
    got = raster(v, t, cal, want.shape)
    print("IOU %.4f  (render %d px, obj %d px, length %.4f m)" % (iou(got, want), want.sum(), got.sum(),
                                                                   np.ptp(v[np.unique(t), 0])))
    if len(args) > 2:
        rgb = np.full(want.shape + (3,), 255, np.uint8)
        rgb[want & got] = (150, 150, 150)
        rgb[want & ~got] = (220, 30, 30)
        rgb[~want & got] = (30, 80, 220)
        ys, xs = np.nonzero(want | got)
        Image.fromarray(rgb[ys.min() - 10:ys.max() + 10, xs.min() - 10:xs.max() + 10]).save(args[2])
