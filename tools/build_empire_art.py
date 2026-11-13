"""Each historical empire's hat and facial hair, cut from the user's own sheets (World Conquest, 2026-11-12).

  beards  Downloads/cecbdd5a-f2e8-4d1d-8d27-d31a00aee4af.webp (moustaches and beards, 10 columns)
  hats    Downloads/fc268d47-2096-41c8-bc7a-6c45ca7decc4.webp (hats, crowns, helmets, 8 columns)
Both are pixel art on white with a caption under each piece. Every piece is found as the ink between
the captions (its separate parts, a moustache and its goatee, stay one piece), cut out with the white
around it made clear, and kept at HI x the Countryball's 32 x 32 grid, so the sheet's detail survives:
an empire's ball is drawn at 128 x 128 (UI/Countryball: the 32 x 32 ball scaled up, the pieces over it).
  hats    the brim just over the eyes (the bottom at row 13; the eyes start on row 14), centred, at most
          30 ball pixels wide and 13 tall (a tall crown may be squashed a little, at most 1.2x)
  beards  a full beard fills the ball's lower face (rows 17.5-29.5, at most 24 wide, squashed at most
          1.6x), a moustache keeps its shape under the eyes; both stay inside the ball's outline
PICKS says which piece each empire wears (sheet row, column); where a sheet has more than one for an
empire the comment lists them.
Writes src/shared/Data/EmpireLooks.luau and tools/assets_out/empire_looks_preview.png.
Run from the project root: py tools/build_empire_art.py
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_empire_looks as L  # noqa: E402  (KEYS, empire_flags, eyes_sprite)

ROOT = L.ROOT
DL = os.path.dirname(ROOT)
BEARDS = "cecbdd5a-f2e8-4d1d-8d27-d31a00aee4af.webp"
HATS = "fc268d47-2096-41c8-bc7a-6c45ca7decc4.webp"
G, CX, CY, R = L.G, L.CX, L.CY, L.R
HI = 4  # the pieces' resolution: HI pixels a ball pixel
N = G * HI
OUT = L.OUT

# (beard (row, col), hat (row, col)), rows and columns from 1 as on the sheets
PICKS = {
    "british": ((1, 1), (1, 1)),
    "german": ((1, 3), (1, 2)),
    "russian": ((1, 5), (1, 4)),
    "ottoman": ((1, 7), (1, 5)),  # beards 1,6 / 1,7; fezzes 1,5 / 1,6
    "japanese": ((1, 9), (1, 7)),  # moustaches 1,9 / 1,10; caps 1,7 / 1,8
    "french": ((2, 1), (2, 1)),
    "austrian": ((2, 3), (2, 2)),  # hats: crown 2,2 / helmet 2,3
    "spanish": ((2, 4), (2, 4)),  # beards 2,4 / 2,5
    "portuguese": ((2, 6), (2, 5)),
    "qing": ((2, 7), (2, 6)),  # moustaches 2,7 / 2,8 / 2,10; hats 2,6 / 2,7
    "persian": ((3, 1), (3, 1)),  # hats: crown 3,1 / plumes 2,8
    "brazilian": ((3, 3), (3, 2)),
    "mexican": ((3, 4), (3, 3)),
    "ethiopian": ((3, 5), (3, 4)),  # beards 3,5 / 3,6; crowns 3,4 / 3,5
    "byzantine": ((3, 7), (3, 6)),
    "roman": ((3, 8), (3, 7)),  # beards 3,8 / 4,1
    "korean": ((4, 2), (3, 8)),  # moustaches 4,2 / 4,3
    "swedish": ((4, 4), (4, 3)),
    "dutch": ((4, 5), (4, 4)),
    "mughal": ((4, 6), (4, 5)),
    "mongol": ((4, 7), (5, 1)),
    "inca": ((5, 1), (5, 2)),  # beards 4,9 / 5,1 / 5,2
    "mali": ((5, 3), (5, 3)),
    "songhai": ((5, 4), (5, 4)),  # beards 4,10 / 5,4
    "ashanti": ((5, 5), (5, 5)),  # hats 5,5 / 5,6 / 5,7 / 5,8
    "zulu": ((5, 6), (6, 1)),
    "vietnamese": ((5, 7), (6, 2)),
    "bulgarian": ((5, 8), (6, 3)),
    "serbian": ((5, 9), (6, 4)),
    "timurid": ((5, 10), (6, 5)),
    "durrani": ((6, 1), (6, 6)),
    "central_african": ((6, 2), (6, 7)),
    "haitian": ((6, 3), (7, 1)),  # crowns 7,1 / 7,2
    "moroccan": ((6, 4), (7, 3)),
    "omani": ((6, 5), (7, 4)),  # turbans 7,4 / 7,5
    "burmese": ((6, 6), (7, 6)),
    "majapahit": ((6, 7), (7, 7)),
    "danish": ((6, 8), (7, 8)),
}


def load(name):
    return np.asarray(Image.open(os.path.join(DL, name)).convert("RGB")).astype(int)


def pieces(a, ncols):
    """{(row, col): mask of the piece's ink} for a sheet with `ncols` columns."""
    ink = (765 - a.sum(axis=2)) > 60
    lab, _ = ndimage.label(ndimage.binary_dilation(ink, iterations=2))
    text = []
    for sl in ndimage.find_objects(lab):
        h = sl[0].stop - sl[0].start
        if h <= 24 and (sl[1].stop - sl[1].start) > 2.5 * h:
            text.append((sl[0].start + sl[0].stop) / 2)
    rows = []
    for y in sorted(text):
        if not rows or y - rows[-1][-1] > 25:
            rows.append([y])
        else:
            rows[-1].append(y)
    caps = [sum(r) / len(r) for r in rows if len(r) >= 2]  # (a caption row has several captions)
    # caption letters touching a piece joined it: rub out every small glyph on a caption row
    raw, _ = ndimage.label(ink, structure=np.ones((3, 3)))
    for i, sl in enumerate(ndimage.find_objects(raw)):
        h = sl[0].stop - sl[0].start
        cy = (sl[0].start + sl[0].stop) / 2
        if h <= 18 and any(abs(cy - c) <= 12 for c in caps):
            ink[sl][raw[sl] == i + 1] = False
    lab, _ = ndimage.label(ndimage.binary_dilation(ink, iterations=2))
    cw = a.shape[1] / ncols
    out = {}
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None:
            continue
        m = (lab == i + 1) & ink
        if m.sum() < 40:
            continue
        cy, cx = (sl[0].start + sl[0].stop) / 2, (sl[1].start + sl[1].stop) / 2
        key = (next((k + 1 for k, c in enumerate(caps) if c > cy), len(caps) + 1), int(cx // cw) + 1)
        out[key] = out[key] | m if key in out else m
    return out


def cut(a, m):
    """The piece as an RGBA image at the sheet's size: its ink, plus the white it encloses unless that
    white is the sheet's own (a pure white hole, inside a wreath or a curl)."""
    ys, xs = np.where(m)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    px, m = a[y0:y1, x0:x1], m[y0:y1, x0:x1]
    full = ndimage.binary_fill_holes(m)
    holes, n = ndimage.label(full & ~m)
    for i in range(1, n + 1):
        h = holes == i
        if px[h].sum(axis=1).mean() >= 748 and h.sum() >= 30:
            full[h] = False
    # the light fringe the upscale left around the dark outline
    edge = full & ~ndimage.binary_erosion(full)
    full[edge & (px.sum(axis=2) > 660)] = False
    rgba = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    rgba[..., :3] = px
    rgba[..., 3] = np.where(full, 255, 0)
    return Image.fromarray(rgba, "RGBA")


def scaled(img, w, h, colours=40):
    """`img` resized to w x h (box filter, colour from opaque pixels only), hard alpha, few colours."""
    a = np.asarray(img).astype(float)
    al = a[..., 3:4] / 255.0
    pre = np.concatenate([a[..., :3] * al, al * 255], axis=2).astype(np.uint8)
    small = np.asarray(Image.fromarray(pre, "RGBA").resize((w, h), Image.BOX)).astype(float)
    alpha = small[..., 3] / 255.0
    rgb = np.where(alpha[..., None] > 0, small[..., :3] / np.maximum(alpha[..., None], 1e-6), 0)
    keep = alpha >= 0.5
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    q = Image.fromarray(rgb, "RGB").quantize(colors=colours, method=Image.Quantize.MEDIANCUT)
    rgb = np.asarray(q.convert("RGB"))
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = rgb
    out[..., 3] = np.where(keep, 255, 0)
    return out


def inside_hi(x, y, shrink):
    """Is hi-res pixel (x, y) inside the ball (in ball pixels, less `shrink`)?"""
    return ((x + 0.5) / HI - CX - 0.5 + 0.5) ** 2 + ((y + 0.5) / HI - CY - 0.5 + 0.5) ** 2 <= (R - shrink) ** 2


def place(arr, x, y, clip=None):
    """A sprite on the N x N canvas: (rows of rgb or None, x, y), trimmed; `clip`: inside the ball."""
    h, w = arr.shape[:2]
    canvas = np.zeros((N, N, 4), np.uint8)
    for j in range(h):
        for i in range(w):
            px, py = x + i, y + j
            if arr[j, i, 3] and 0 <= px < N and 0 <= py < N and (clip is None or inside_hi(px, py, clip)):
                canvas[py, px] = arr[j, i]
    return canvas


def hat(img):
    w0, h0 = img.size
    sy = min(30 * HI / w0, 13 * HI / h0)
    sx = min(30 * HI / w0, sy * 1.2)
    w, h = max(2, round(w0 * sx)), max(2, round(h0 * sy))
    return place(scaled(img, w, h), round(N / 2 - w / 2), 13 * HI - h)


def beard(img, kscale):
    w0, h0 = img.size
    if h0 / w0 < 0.62:  # a moustache: its own shape, under the eyes
        s = min(kscale, 20 * HI / w0, 9 * HI / h0)
        w, h = max(2, round(w0 * s)), max(2, round(h0 * s))
        return place(scaled(img, w, h), round(N / 2 - w / 2), round(18.5 * HI), clip=0.9)
    sy = min(12 * HI / h0, kscale * 1.4)
    sx = min(24 * HI / w0, sy * 1.6)
    w, h = max(2, round(w0 * sx)), max(2, round(h0 * sy))
    return place(scaled(img, w, h), round(N / 2 - w / 2), round(17.5 * HI), clip=0.9)


# ---------------------------------------------------------------- the module
ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-/:;<=>?@^_`{|}~"


def encode(canvas):
    """{ x, y, w, h, pal, data }: the trimmed sprite, `data` its rows run-length coded ("." clear, a
    palette letter a pixel, a count before a run of more than one)."""
    ys, xs = np.where(canvas[..., 3] > 0)
    if len(ys) == 0:
        return None
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    c = canvas[y0:y1, x0:x1]
    pal, idx = [], {}
    cells = []
    for row in c:
        for p in row:
            if p[3] == 0:
                cells.append(".")
                continue
            k = (int(p[0]), int(p[1]), int(p[2]))
            if k not in idx:
                idx[k] = ALPHA[len(pal)]
                pal.append(k)
            cells.append(idx[k])
    assert len(pal) <= len(ALPHA), len(pal)
    data, i = [], 0
    while i < len(cells):
        j = i
        while j < len(cells) and cells[j] == cells[i]:
            j += 1
        n = j - i
        data.append((str(n) if n > 1 else "") + cells[i])
        i = j
    return {"x": int(x0), "y": int(y0), "w": int(x1 - x0), "h": int(y1 - y0), "pal": pal, "data": "".join(data)}


def lua(sp):
    pal = ", ".join("{ %d, %d, %d }" % p for p in sp["pal"])
    return '{ x = %d, y = %d, w = %d, h = %d, pal = { %s }, data = "%s" }' % (
        sp["x"], sp["y"], sp["w"], sp["h"], pal, sp["data"])


# ---------------------------------------------------------------- the preview, as the game draws it
def ball_hi(key, look):
    flags = L.empire_flags()
    pal, ix = flags.get(key, ([(150, 156, 170)], "0" * 600))
    base = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    for y in range(G):
        for x in range(G):
            dx, dy = x - CX, y - CY
            d = (dx * dx + dy * dy) ** 0.5
            if d <= R + 0.5:
                if d > R - 0.6:
                    base.putpixel((x, y), OUT + (255,))
                    continue
                u = min(max((x - (CX - R)) / (2 * R), 0), 0.999)
                v = min(max((y - (CY - R)) / (2 * R), 0), 0.999)
                c = pal[L.FIDX.index(ix[int(v * 20) * 30 + int(u * 30)])]
                nx, ny = dx / max(d, 1e-6), dy / max(d, 1e-6)
                if (R - d) < 2.4 and (nx * 0.85 - ny * 0.25 > 0.45 or ny > 0.55):
                    c = tuple(int(q * 0.8 + 0.5) for q in c)
                base.putpixel((x, y), c + (255,))
    big = base.resize((N, N), Image.NEAREST)
    big.alpha_composite(Image.fromarray(look[1], "RGBA"))
    ex, ey, epal, erows = L.eyes_sprite()
    eyes = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    for j, row in enumerate(erows):
        for i, ch in enumerate(row):
            if ch in epal:
                eyes.putpixel((ex + i, ey + j), epal[ch] + (255,))
    big.alpha_composite(eyes.resize((N, N), Image.NEAREST))
    big.alpha_composite(Image.fromarray(look[0], "RGBA"))
    return big


def main():
    ba, ha = load(BEARDS), load(HATS)
    bp, hp = pieces(ba, 10), pieces(ha, 8)
    # the beard sheet's scale: its widest full beard 24 ball pixels wide
    kscale = 22 * HI / max(np.ptp(np.where(m)[1]) + 1 for m in bp.values())
    looks = {}
    for k in L.KEYS:
        (br, bc), (hr, hc) = PICKS[k]
        assert (br, bc) in bp, ("beard", k, br, bc)
        assert (hr, hc) in hp, ("hat", k, hr, hc)
        looks[k] = (hat(cut(ha, hp[(hr, hc)])), beard(cut(ba, bp[(br, bc)]), kscale))
    parts = []
    for k in L.KEYS:
        hs, bs = encode(looks[k][0]), encode(looks[k][1])
        parts.append("\t%s = {\n\t\that = %s,\n\t\tbeard = %s,\n\t}," % (k, lua(hs), lua(bs)))
    mod = (
        "--!strict\n"
        "-- GENERATED by tools/build_empire_art.py from the user's empire hat and beard sheets. Do not edit.\n"
        "-- (World Conquest, 2026-11-12) Each historical empire's own hat and facial hair, by the empire's flag\n"
        "-- key (Data/Empires.HISTORICAL, \"emp_<key>\"), at HI x the ball's 32 x 32 grid: UI/Countryball draws an\n"
        "-- empire's ball at 128 x 128 with these over it (x, y, w, h on that canvas; pal; data: the rows\n"
        "-- run-length coded, \".\" clear, a palette letter (ALPHA order) a pixel, a count before a run).\n"
        "-- The player's own gear replaces them.\n"
        "return {\n\tHI = %d,\n\tALPHA = \"%s\",\n" % (HI, ALPHA.replace("\\", "\\\\").replace('"', '\\"')) + "\n".join(parts) + "\n}\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "EmpireLooks.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    S, cols = 2, 10
    rows_n = (len(L.KEYS) + cols - 1) // cols
    cell = N * S + 20
    sheet = Image.new("RGBA", (cols * cell + 20, rows_n * cell + 20), (24, 30, 50, 255))
    for i, k in enumerate(L.KEYS):
        big = ball_hi(k, looks[k]).resize((N * S, N * S), Image.NEAREST)
        sheet.alpha_composite(big, (20 + (i % cols) * cell, 20 + (i // cols) * cell))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "empire_looks_preview.png"))
    print("ok", len(L.KEYS), "module", len(mod), "chars")


if __name__ == "__main__":
    main()
