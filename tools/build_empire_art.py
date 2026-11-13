"""Each historical empire's hat and facial hair, cut from the user's own sheets (World Conquest, 2026-11-12).

  beards  Downloads/cecbdd5a-f2e8-4d1d-8d27-d31a00aee4af.webp (moustaches and beards, 10 columns)
  hats    Downloads/fc268d47-2096-41c8-bc7a-6c45ca7decc4.webp (hats, crowns, helmets, 8 columns)
Both are pixel art on white with a caption under each piece. Every piece is found as the ink between
the captions (its separate parts, a moustache and its goatee, stay one piece), cut out with the white
around it made clear, and kept at HI x the Countryball's 32 x 32 grid, so the sheet's detail survives:
sized as on the user's sheet of finished empire balls (Downloads/2778f313-...webp; never larger than
the sheet, the colours merged a little to fit the palette):
an empire's ball is drawn at HI x (UI/Countryball: the 32 x 32 ball scaled up, the pieces over it), on
a canvas TOP ball pixels taller above the ball and BOT below, so a tall crown rises over the head and a
long beard hangs under the chin while the ball keeps its size on screen.
  hats    centred, their bottom on the brim line just over the eyes (row 13; the eyes start on row 14),
          HAT_DY moving a piece whose lowest part hangs (pearl strings, a keffiyeh's cloth)
  beards  centred, their top just under the eyes (row 18.5), BEARD_DY moving one
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


# (2026-11-12, after the user's reference sheet of finished empire balls, Downloads/2778f313-...webp:
# the hat about as wide as the ball, over its top third, the brim just over the eyes; the beard small,
# inside the lower half under the eyes.) Sizes in parts of the ball's diameter D.
D = 2 * R * HI
HAT_W, HAT_H = 0.9, 0.78  # a hat at most this wide and tall
WIDE_W, WIDE_H = 1.18, 0.62  # a wide hat (bicorne, tricorne, gat, straw hat: wider than 1.35 x its height)
BEARD_W, BEARD_H = 0.66, 0.4  # a beard inside the lower face (rows 18.5 down to the ball's bottom)
TACHE_W, TACHE_H = 0.5, 0.2  # a moustache
# per piece fine-tuning, in canvas pixels (+ down); and size (x)
HAT_DY = {"byzantine": 6, "moroccan": 12, "ashanti": 4, "korean": 4, "japanese": 2}
HAT_K = {}
BEARD_DY = {}
BEARD_K = {}
COLOURS = 76  # (len(ALPHA))


def few_colours(img):
    """The piece with at most COLOURS colours (median cut, no dither) and hard alpha: (h, w, 4) uint8."""
    a = np.asarray(img)
    keep = a[..., 3] > 0
    q = Image.fromarray(a[..., :3], "RGB").quantize(colors=COLOURS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = np.zeros(a.shape, np.uint8)
    out[..., :3] = np.asarray(q.convert("RGB"))
    out[..., 3] = np.where(keep, 255, 0)
    return out


def resized(img, k):
    """`img` (RGBA) at k x its size: a box filter over its opaque pixels only, hard alpha (k >= 1: the
    sheet's own pixels)."""
    if k >= 0.999:
        return img
    w, h = max(2, round(img.width * k)), max(2, round(img.height * k))
    a = np.asarray(img).astype(float)
    al = a[..., 3:4] / 255.0
    pre = np.concatenate([a[..., :3] * al, al * 255], axis=2).astype(np.uint8)
    sm = np.asarray(Image.fromarray(pre, "RGBA").resize((w, h), Image.BOX)).astype(float)
    alpha = sm[..., 3] / 255.0
    rgb = np.clip(sm[..., :3] / np.maximum(alpha[..., None], 1e-6), 0, 255)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = rgb.astype(np.uint8)
    out[..., 3] = np.where(alpha >= 0.5, 255, 0)
    return Image.fromarray(out, "RGBA")


def clip_ball(a, x, y, shrink=0.9):
    """Clears the piece's pixels outside the ball's outline."""
    h, w = a.shape[:2]
    jj, ii = np.mgrid[0:h, 0:w]
    bx = (x + ii + 0.5) / HI
    by = (y + jj + 0.5) / HI
    out = (bx - CX - 0.5) ** 2 + (by - CY - 0.5) ** 2 > (R - shrink) ** 2
    a = a.copy()
    a[out, 3] = 0
    return a


def hat(img, key):
    w0, h0 = img.size
    wide = w0 > 1.35 * h0
    mw, mh = (WIDE_W, WIDE_H) if wide else (HAT_W, HAT_H)
    k = min(1.0, mw * D / w0, mh * D / h0) * HAT_K.get(key, 1.0)
    a = few_colours(resized(img, k))
    h, w = a.shape[:2]
    return a, G * HI // 2 - w // 2, 13 * HI - h + HAT_DY.get(key, 0)


def beard(img, key):
    w0, h0 = img.size
    tache = h0 < 0.62 * w0
    mw, mh = (TACHE_W, TACHE_H) if tache else (BEARD_W, BEARD_H)
    k = min(1.0, mw * D / w0, mh * D / h0) * BEARD_K.get(key, 1.0)
    a = few_colours(resized(img, k))
    h, w = a.shape[:2]
    x, y = G * HI // 2 - w // 2, round(18.5 * HI) + BEARD_DY.get(key, 0)
    return clip_ball(a, x, y), x, y


# ---------------------------------------------------------------- the module
ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-/:;<=>?@^_`{|}~"
assert len(ALPHA) >= COLOURS


def encode(piece):
    """{ x, y, w, h, pal, data }: `data` its rows run-length coded ("." clear, a palette letter a pixel,
    a count before a run of more than one); x, y on the ball's HI x canvas (y < 0: above the ball)."""
    a, x, y = piece
    ys, xs = np.where(a[..., 3] > 0)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    c = a[y0:y1, x0:x1]
    pal, idx, cells = [], {}, []
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
    data, i = [], 0
    while i < len(cells):
        j = i
        while j < len(cells) and cells[j] == cells[i]:
            j += 1
        data.append((str(j - i) if j - i > 1 else "") + cells[i])
        i = j
    return {"x": int(x + x0), "y": int(y + y0), "w": int(x1 - x0), "h": int(y1 - y0), "pal": pal, "data": "".join(data)}


def lua(sp):
    pal = ", ".join("{ %d, %d, %d }" % p for p in sp["pal"])
    return '{ x = %d, y = %d, w = %d, h = %d, pal = { %s }, data = "%s" }' % (
        sp["x"], sp["y"], sp["w"], sp["h"], pal, sp["data"])


# ---------------------------------------------------------------- the preview, as the game draws it
def ball_hi(key, look, top, bot):
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
    W, H = G * HI, (G + top + bot) * HI
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(base.resize((W, G * HI), Image.NEAREST), (0, top * HI))

    def put(piece):
        a, x, y = piece
        out.alpha_composite(Image.fromarray(a, "RGBA"), (x, y + top * HI))

    put(look[1])
    ex, ey, epal, erows = L.eyes_sprite()
    eyes = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    for j, row in enumerate(erows):
        for i, ch in enumerate(row):
            if ch in epal:
                eyes.putpixel((ex + i, ey + j), epal[ch] + (255,))
    out.alpha_composite(eyes.resize((W, G * HI), Image.NEAREST), (0, top * HI))
    put(look[0])
    return out


def main():
    ba, ha = load(BEARDS), load(HATS)
    bp, hp = pieces(ba, 10), pieces(ha, 8)
    looks = {}
    for k in L.KEYS:
        (br, bc), (hr, hc) = PICKS[k]
        assert (br, bc) in bp, ("beard", k, br, bc)
        assert (hr, hc) in hp, ("hat", k, hr, hc)
        looks[k] = (hat(cut(ha, hp[(hr, hc)]), k), beard(cut(ba, bp[(br, bc)]), k))
    # the room the pieces need above and below the ball, in ball pixels (the same for every empire)
    top = max(0, -min(min(h[2], b[2]) for h, b in looks.values()))
    bot = max(0, max(max(h[2] + h[0].shape[0], b[2] + b[0].shape[0]) for h, b in looks.values()) - G * HI)
    top, bot = -(-top // HI), -(-bot // HI)
    for h, b in looks.values():
        assert h[1] >= 0 and h[1] + h[0].shape[1] <= G * HI, "a hat wider than the ball's canvas"
    parts = []
    for k in L.KEYS:
        parts.append("\t%s = {\n\t\that = %s,\n\t\tbeard = %s,\n\t}," % (k, lua(encode(looks[k][0])), lua(encode(looks[k][1]))))
    mod = (
        "--!strict\n"
        "-- GENERATED by tools/build_empire_art.py from the user's empire hat and beard sheets (copied 1:1).\n"
        "-- Do not edit.\n"
        "-- (World Conquest, 2026-11-12) Each historical empire's own hat and facial hair, by the empire's flag\n"
        "-- key (Data/Empires.HISTORICAL, \"emp_<key>\"). UI/Countryball draws an empire's ball at HI x its 32 x 32\n"
        "-- grid on a canvas TOP ball pixels taller above the ball and BOT below, these pieces over it: x, y on\n"
        "-- that HI x grid (y < 0: above the ball), pal, data: the rows run-length coded (\".\" clear, a palette\n"
        "-- letter in ALPHA order a pixel, a count before a run). The player's own gear replaces them.\n"
        "return {\n\tHI = %d,\n\tTOP = %d,\n\tBOT = %d,\n\tALPHA = \"%s\",\n" % (HI, top, bot, ALPHA)
        + "\n".join(parts) + "\n}\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "EmpireLooks.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    cols = 10
    cw, ch = G * HI + 24, (G + top + bot) * HI + 24
    rows_n = (len(L.KEYS) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw + 24, rows_n * ch + 24), (24, 30, 50, 255))
    for i, k in enumerate(L.KEYS):
        sheet.alpha_composite(ball_hi(k, looks[k], top, bot), (24 + (i % cols) * cw, 24 + (i // cols) * ch))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "empire_looks_preview.png"))
    print("ok", len(L.KEYS), "top", top, "bot", bot, "module", len(mod), "chars")


if __name__ == "__main__":
    main()
