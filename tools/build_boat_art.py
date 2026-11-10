"""The default boats from the user's pictures (Take Over the World!, 2026-11-09).

Pictures (C:/Users/izzyn/Downloads, 1024 x 1024 at 8 px a pixel, navy background):
  unit     ddfb1fa1-...webp  the army's landing boat (bow to the left), four helmeted Countryballs
  warship  03e65ea9-...webp  a frigate (bow to the right) with a big helmeted Countryball
  trade    84b29933-...webp  a container ship (bow to the right)
Each is sampled on its 8 px grid (the median of each cell's middle), the background (navy reaching
the border) and the water line under the hull are cleared, the colours are merged to a palette, and
the Countryballs' flag pixels are marked so the game paints them in the owner's flag
(Countryball.boat_content). Writes src/shared/Data/BoatArt.luau and tools/assets_out/boat_art_preview.png.
Run from the project root: py tools/build_boat_art.py
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = "C:/Users/izzyn/Downloads/"
P = 8  # source px a pixel
CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-/:;<=>?@[]^_{|}~"
OUTLINE = (14, 16, 24)

# key -> (picture, bow faces, flag look, eye boxes kept as drawn (x0, y0, x1, y1 on the 128 grid))
# flag look: "red" = only the balls' red is flag (small balls: helmet, eye row, red below);
# "ball" = the red and the white under the helmet (a big ball: its whole face)
BOATS = {
    "unit": ("ddfb1fa1-6ab5-45d4-b6fe-71682f151c8c.webp", "left", "red", []),
    "warship": ("03e65ea9-0353-4465-a784-c01fa16556dc.webp", "right", "ball", [(79, 54, 84, 57), (86, 54, 91, 57)]),
    "trade": ("84b29933-7120-4760-b8a0-08054c858b81.webp", "right", None, []),
}


def grid(name):
    im = np.asarray(Image.open(DL + name).convert("RGB")).astype(int)
    n = im.shape[0] // P
    g = np.zeros((n, n, 3), int)
    for j in range(n):
        for i in range(n):
            g[j, i] = np.median(im[P * j + 2 : P * j + 6, P * i + 2 : P * i + 6].reshape(-1, 3), axis=0)
    return g, im[4, 4]


def is_red(c):
    r, g, b = c
    return r > 80 and r > g * 2 and r > b * 1.6 and g < 70


def is_white(c):
    return min(c) > 150 and max(c) - min(c) < 30


def is_water(c):
    r, g, b = c
    return b > r + 40 and b > 150 and g > 120 and r > 50  # light blue (the navy hulls are darker)


def build_one(key, name, facing, look, eyes):
    g, bg = grid(name)
    n = g.shape[0]
    near = np.abs(g - bg).sum(2) < 30
    lab, _ = ndimage.label(near)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    clear = np.isin(lab, list(edge))
    # the water line and its spray: light blue (and white flecks) at and under the hull's bottom
    solid = ~clear
    waterm = np.array([[is_water(tuple(g[j, i])) for i in range(n)] for j in range(n)]) & solid
    rows_w = np.where(waterm.sum(1) > 6)[0]
    if len(rows_w):
        wl = rows_w.min()
        for j in range(wl, n):
            for i in range(n):
                c = tuple(g[j, i])
                if waterm[j, i] or is_white(c) or (solid[j, i] and j > wl):
                    clear[j, i] = True
        # flecks above the line (spray), not touching the hull
        lab2, _ = ndimage.label(~clear)
        sizes = ndimage.sum(np.ones_like(lab2), lab2, range(lab2.max() + 1))
        for k, s in enumerate(sizes):
            if k and s < 6:
                clear[lab2 == k] = True
    # the flag pixels: red clusters are balls (with "ball", the white of the face joins its red)
    red = np.array([[is_red(tuple(g[j, i])) for i in range(n)] for j in range(n)]) & ~clear
    if look is None:  # no Countryballs aboard
        red[:] = False
    flag = red.copy()
    balls = []
    rl, rn = ndimage.label(red)
    for sl in ndimage.find_objects(rl):
        if (sl[0].stop - sl[0].start) * (sl[1].stop - sl[1].start) < 6:
            flag[sl] = False
            continue
        y0, y1, x0, x1 = sl[0].start, sl[0].stop - 1, sl[1].start, sl[1].stop - 1
        if look == "ball":
            # the white face over the red, up to the helmet's brim (a dark row)
            yt = y0
            while yt > 0 and any(is_white(tuple(g[yt - 1, i])) for i in range(x0, x1 + 1)):
                yt -= 1
            for j in range(yt, y0 + 1):
                for i in range(x0 - 2, x1 + 3):
                    if is_white(tuple(g[j, i])) and not any(a <= i <= c and b <= j <= d for a, b, c, d in eyes):
                        flag[j, i] = True
            balls.append((x0, yt, x1, y1, 0.0))
        else:
            balls.append((x0, y0, x1, y1, 0.35))
    ys, xs = np.where(~clear)
    X0, X1, Y0, Y1 = xs.min(), xs.max(), ys.min(), ys.max()
    rows, fl = [], []
    for j in range(Y0, Y1 + 1):
        r, f = [], ""
        for i in range(X0, X1 + 1):
            if clear[j, i]:
                r.append(None)
                f += "."
                continue
            c = tuple(int(v) for v in g[j, i])
            if near[j, i] or sum(c) < 60:
                c = OUTLINE if sum(c) < 60 else c
            if flag[j, i]:
                f += "f" if (is_red(c) and c[0] < 165) or (is_white(c) and max(c) < 200) else "F"
                r.append((128, 128, 128))
            else:
                f += "."
                r.append(c)
        rows.append(r)
        fl.append(f)
    rows = merge(rows)
    balls = [(a - X0, b - Y0, c - X0, d - Y0, v) for a, b, c, d, v in balls]
    if facing == "left":  # stored facing right
        rows = [r[::-1] for r in rows]
        fl = [f[::-1] for f in fl]
        w = X1 - X0
        balls = [(w - c, b, w - a, d, v) for a, b, c, d, v in balls]
    return rows, fl, balls


def merge(rows, tol=18):
    """Colours within `tol` of a kept one take its value, until the palette fits CHARS."""
    while True:
        kept, out = [], []
        for r in rows:
            row = []
            for c in r:
                if c is not None:
                    for k in kept:
                        if sum(abs(a - b) for a, b in zip(c, k)) <= tol:
                            c = k
                            break
                    else:
                        kept.append(c)
                row.append(c)
            out.append(row)
        if len(kept) <= len(CHARS):
            return out
        tol += 4


def lua(key, rows, fl, balls):
    idx = {}
    lines = []
    for r in rows:
        s = ""
        for c in r:
            if c is None:
                s += "."
            else:
                if c not in idx:
                    idx[c] = CHARS[len(idx)]
                s += idx[c]
        lines.append(s)
    pal = ", ".join('["%s"] = { %d, %d, %d }' % (ch, *c) for c, ch in idx.items())
    body = "\n".join('\t\t\t"%s",' % s for s in lines)
    fb = "\n".join('\t\t\t"%s",' % s for s in fl)
    bs = ", ".join("{ %d, %d, %d, %d, %.2f }" % b for b in balls)
    return (
        "\t%s = {\n\t\tw = %d,\n\t\th = %d,\n\t\tpal = { %s },\n\t\trows = {\n%s\n\t\t},\n"
        "\t\tballs = { %s },\n\t\tflag = {\n%s\n\t\t},\n\t},"
    ) % (key, len(rows[0]), len(rows), pal, body, bs, fb)


FLAGS = {  # preview flags: vertical / horizontal stripes
    "pl": ("h", [(255, 255, 255), (220, 20, 60)]),
    "fr": ("v", [(0, 85, 164), (255, 255, 255), (239, 65, 53)]),
    "de": ("h", [(0, 0, 0), (221, 0, 0), (255, 206, 0)]),
    "br": ("h", [(0, 156, 59), (255, 223, 0), (0, 39, 118)]),
}


def flag_rgb(code, u, v):
    how, cols = FLAGS[code]
    t = u if how == "v" else v
    return cols[min(len(cols) - 1, int(t * len(cols)))]


def paint(rows, fl, balls, code):
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for j in range(h):
        for i in range(w):
            c = rows[j][i]
            if c is None:
                continue
            if fl[j][i] in "Ff":
                b = next((b for b in balls if b[0] - 2 <= i <= b[2] + 2 and b[1] <= j <= b[3]), balls[0])
                u = (i - b[0]) / max(1, b[2] - b[0])
                v = b[4] + (1 - b[4]) * (j - b[1]) / max(1, b[3] - b[1])
                c = flag_rgb(code, u, v)
                if fl[j][i] == "f":
                    c = tuple(int(x * 0.72) for x in c)
            img.putpixel((i, j), (*c, 255))
    return img


def main():
    items, made = [], {}
    for key, (name, facing, look, eyes) in BOATS.items():
        rows, fl, balls = build_one(key, name, facing, look, eyes)
        made[key] = (rows, fl, balls)
        items.append(lua(key, rows, fl, balls))
        print(key, len(rows[0]), "x", len(rows), "balls", len(balls))
    src = (
        "--!strict\n"
        "-- GENERATED by tools/build_boat_art.py from the user's pictures (2026-11-09). Do not edit.\n"
        "-- The default boats (Countryball.boat_content): the army's landing boat (transports), the warship\n"
        "-- and the trade ship, facing right. pal = character -> {r, g, b}, rows top to bottom (\".\" clear);\n"
        "-- `flag` marks the Countryballs' flag pixels (F lit, f in shade) on the same grid, painted in the\n"
        "-- owner's flag; balls = { x0, y0, x1, y1, v0 }: each ball's flag box (0-based) and the flag height\n"
        "-- its top row shows (0 = the flag's top: a whole face; 0.35 = under the helmet and the eyes).\n"
        "local BoatArt = {}\n\n"
        "BoatArt.boats = {\n" + "\n".join(items) + "\n}\n\n"
        "return BoatArt\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "BoatArt.luau"), "w", encoding="utf-8", newline="\n").write(src)
    # the preview: each boat in four flags, both facings, at 3x
    S = 3
    tiles = []
    for key, (rows, fl, balls) in made.items():
        for code in FLAGS:
            im = paint(rows, fl, balls, code)
            tiles.append(im)
            tiles.append(im.transpose(Image.FLIP_LEFT_RIGHT))
    cw = max(t.width for t in tiles) + 8
    ch = max(t.height for t in tiles) + 8
    sheet = Image.new("RGBA", (cw * 8 * S, ch * len(BOATS) * S), (24, 60, 110, 255))
    for k, t in enumerate(tiles):
        t = t.resize((t.width * S, t.height * S), Image.NEAREST)
        sheet.alpha_composite(t, ((k % 8) * cw * S, (k // 8) * ch * S))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "boat_art_preview.png"))
    print("BoatArt.luau written")


if __name__ == "__main__":
    main()
