"""Each historical empire's hat and facial hair from the user's own sheets (World Conquest, 2026-11-12).

Replaces the hand-drawn looks of tools/build_empire_looks.py with the user's improved pixel art:
  beards  Downloads/cecbdd5a-f2e8-4d1d-8d27-d31a00aee4af.webp (moustaches and beards, 10 columns)
  hats    Downloads/fc268d47-2096-41c8-bc7a-6c45ca7decc4.webp (hats, crowns, helmets, 8 columns)
Both are pixel art on white with a caption under each piece. Every piece is found as the ink between
the captions (connected parts, so a moustache and its separate goatee stay one piece), cut out
(the white reaching its border is the background; white it encloses, a turban's, stays), sampled
down to the Countryball's 32 x 32 canvas and written to src/shared/Data/EmpireLooks.luau in the same
format as before ({ [flag key] = { hat = sprite, beard = sprite } }).
  hats   one scale for the whole sheet (the widest hat about 26 px), the bottom on row 11 just over the
         eyes; a tall crown is squashed a little (at most 1.6x) to stay within the 12 rows over them
  beards one scale for the whole sheet (a full beard about 22 px), the top on row 18 under the eyes,
         at most 11 rows tall, kept inside the ball's outline
PICKS says which piece each empire wears (sheet row, column); where the sheet has two or more for an
empire, the first one listed in the comment was chosen.
Run from the project root: py tools/build_empire_art.py
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_empire_looks as L  # noqa: E402  (KEYS, render_ball, to_sprite, lua_sprite)

ROOT = L.ROOT
DL = os.path.dirname(ROOT)
BEARDS = "cecbdd5a-f2e8-4d1d-8d27-d31a00aee4af.webp"
HATS = "fc268d47-2096-41c8-bc7a-6c45ca7decc4.webp"
G, CX, CY, R = L.G, L.CX, L.CY, L.R
OUTLINE = (18, 20, 28)

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
    """{(row, col): (mask of the piece's ink, bbox)} for a sheet with `ncols` columns."""
    ink = (765 - a.sum(axis=2)) > 60
    lab, n = ndimage.label(ndimage.binary_dilation(ink, iterations=2))
    objs = ndimage.find_objects(lab)
    text, items = [], []
    for i, sl in enumerate(objs):
        h = sl[0].stop - sl[0].start
        cy = (sl[0].start + sl[0].stop) / 2
        cx = (sl[1].start + sl[1].stop) / 2
        (text if h <= 24 and (sl[1].stop - sl[1].start) > 2.5 * h else items).append((i + 1, sl, cx, cy))
    # the caption rows: text centres, clustered
    ys = sorted(t[3] for t in text)
    rows = []
    for y in ys:
        if not rows or y - rows[-1][-1] > 25:
            rows.append([y])
        else:
            rows[-1].append(y)
    caps = [sum(r) / len(r) for r in rows if len(r) >= 2]  # (a caption row has several captions)
    # the caption letters touching a piece were joined to it: rub out every small glyph on a caption row,
    # then find the pieces again
    raw, _ = ndimage.label(ink, structure=np.ones((3, 3)))
    for i, sl in enumerate(ndimage.find_objects(raw)):
        h = sl[0].stop - sl[0].start
        cy = (sl[0].start + sl[0].stop) / 2
        if h <= 18 and any(abs(cy - c) <= 12 for c in caps):
            ink[sl][raw[sl] == i + 1] = False
    lab, n = ndimage.label(ndimage.binary_dilation(ink, iterations=2))
    items = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None or (ink[sl] & (lab[sl] == i + 1)).sum() < 40:
            continue
        items.append((i + 1, sl, (sl[1].start + sl[1].stop) / 2, (sl[0].start + sl[0].stop) / 2))
    cw = a.shape[1] / ncols
    out = {}
    for lid, sl, cx, cy in items:
        row = next((k + 1 for k, c in enumerate(caps) if c > cy), len(caps) + 1)
        col = int(cx // cw) + 1
        m = (lab == lid) & ink
        if (row, col) in out:
            out[(row, col)] = out[(row, col)] | m
        else:
            out[(row, col)] = m
    return out


def cut(a, m):
    """The piece's pixels and its mask (its ink plus the white it encloses), cropped."""
    ys, xs = np.where(m)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    m = ndimage.binary_fill_holes(m[y0:y1, x0:x1])
    return a[y0:y1, x0:x1], m


def sample(px, m, w, h):
    """`px` sampled down to w x h cells: rows of (r, g, b) or None."""
    H, W = m.shape
    out = []
    for j in range(h):
        ya, yb = int(j * H / h), max(int((j + 1) * H / h), int(j * H / h) + 1)
        row = []
        for i in range(w):
            xa, xb = int(i * W / w), max(int((i + 1) * W / w), int(i * W / w) + 1)
            mm = m[ya:yb, xa:xb]
            if mm.mean() < 0.45:
                row.append(None)
                continue
            c = np.median(px[ya:yb, xa:xb][mm], axis=0)
            row.append(OUTLINE if c.sum() < 90 else tuple(int(v) for v in c))
        out.append(row)
    return out


def quantise(rows, k):
    cols = np.array([c for r in rows for c in r if c is not None], dtype=float)
    uniq = np.unique(cols, axis=0)
    if len(uniq) <= k:
        return rows
    rng = np.random.default_rng(5)
    cent = uniq[rng.choice(len(uniq), k, replace=False)]
    for _ in range(30):
        lab = ((cols[:, None, :] - cent[None]) ** 2).sum(2).argmin(1)
        for i in range(k):
            if (lab == i).any():
                cent[i] = cols[lab == i].mean(0)
    return [
        [None if c is None else tuple(int(v) for v in cent[((cent - np.array(c)) ** 2).sum(1).argmin()]) for c in r]
        for r in rows
    ]


def canvas(rows, x, y, clip=None):
    img = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    for j, r in enumerate(rows):
        for i, c in enumerate(r):
            px, py = x + i, y + j
            if c is None or not (0 <= px < G and 0 <= py < G):
                continue
            if clip is not None and (px + 0.5 - CX) ** 2 + (py + 0.5 - CY) ** 2 > (R - clip) ** 2:
                continue
            img.putpixel((px, py), c + (255,))
    return img


def hat(a, m, scale):
    px, mm = cut(a, m)
    h0, w0 = mm.shape
    sx = min(scale, 26 / w0, 12 * 1.6 / h0)
    sy = min(sx, 12 / h0)
    w, h = max(3, round(w0 * sx)), max(2, round(h0 * sy))
    rows = quantise(sample(px, mm, w, h), 14)
    return canvas(rows, int(round(CX - w / 2 + 0.5)), 12 - h)


def beard(a, m, scale):
    px, mm = cut(a, m)
    h0, w0 = mm.shape
    sx = min(scale, 24 / w0, 11 * 1.6 / h0)
    sy = min(sx, 11 / h0)
    w, h = max(3, round(w0 * sx)), max(2, round(h0 * sy))
    rows = quantise(sample(px, mm, w, h), 10)
    return canvas(rows, int(round(CX - w / 2 + 0.5)), 18, clip=1.0)


def main():
    ba, ha = load(BEARDS), load(HATS)
    bp, hp = pieces(ba, 10), pieces(ha, 8)
    # one scale a sheet: its widest piece fills the target width
    bscale = 22 / max(np.ptp(np.where(m)[1]) + 1 for m in bp.values())
    hscale = 26 / max(np.ptp(np.where(m)[1]) + 1 for m in hp.values())
    missing = [k for k in L.KEYS if k not in PICKS]
    assert not missing, missing
    looks = {}
    for k in L.KEYS:
        (br, bc), (hr, hc) = PICKS[k]
        assert (br, bc) in bp, ("beard", k, br, bc, sorted(bp))
        assert (hr, hc) in hp, ("hat", k, hr, hc, sorted(hp))
        looks[k] = (hat(ha, hp[(hr, hc)], hscale), beard(ba, bp[(br, bc)], bscale))
    parts = []
    for k in L.KEYS:
        hs, bs = L.to_sprite(looks[k][0], False), L.to_sprite(looks[k][1], True)
        assert len(hs["pal"]) <= 52 and len(bs["pal"]) <= 52
        parts.append("\t%s = {\n\t\that = %s,\n\t\tbeard = %s,\n\t}," % (k, L.lua_sprite(hs), L.lua_sprite(bs)))
    mod = (
        "--!strict\n"
        "-- GENERATED by tools/build_empire_art.py from the user's empire hat and beard sheets. Do not edit.\n"
        "-- (World Conquest, 2026-11-12) Each historical empire's own hat and facial hair on its Countryball\n"
        "-- (UI/Countryball): by the empire's flag key (Data/Empires.HISTORICAL, \"emp_<key>\"), in GearSprites'\n"
        "-- sprite format (x, y on the 32 x 32 ball, pal, rows). The player's own gear replaces them.\n"
        "return {\n" + "\n".join(parts) + "\n}\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "EmpireLooks.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    # preview, drawn as the game draws it (L.render_ball): 4x, 10 a row, with the empire's name key
    S, cols = 6, 10
    rows_n = (len(L.KEYS) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (G + 6) * S + 12, rows_n * (G + 6) * S + 12), (24, 30, 50, 255))
    for i, k in enumerate(L.KEYS):
        big = L.render_ball(k, looks[k]).resize((G * S, G * S), Image.NEAREST)
        sheet.alpha_composite(big, (6 + (i % cols) * (G + 6) * S, 6 + (i // cols) * (G + 6) * S))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "empire_looks_preview.png"))
    print("ok", len(L.KEYS), "beard pieces", len(bp), "hat pieces", len(hp))


if __name__ == "__main__":
    main()
