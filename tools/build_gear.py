"""Countryball gear, the item shop backdrop and the item shop icon (Take Over the World!, 2026-11-08).

From the user's reference sheets in Downloads (pixel art upscaled about 8x on a navy background):
  hats    92571330-f1ad-4796-a8ff-5fa6432f8875.webp
  beards  dd91cbb2-f9e4-4b94-9f12-2042f27daf0c.webp (beards, moustaches, horns)
  glasses a96a34ee-b6af-45fb-97c1-6e987df3a1cf.webp
Each sprite is cut out of its sheet, sampled back down to pixels at the size it is worn on the
32 x 32 Countryball and written, with recoloured variants, to src/shared/Data/GearSprites.luau.
  backdrop  images.jpg -> tools/assets_out/shop_bg2.png (pixelated, 256 x 144, ten blue-greys)
  icon      Itemshop icon.webp -> tools/assets_out/icons/item_shop_basket.png (its baked-in
            checkerboard removed, pixelated)
Previews go to tools/assets_out/gear_preview.png.
"""
import colorsys
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, "tools", "assets_out")
LUA = os.path.join(ROOT, "src", "shared", "Data", "GearSprites.luau")

HATS = "92571330-f1ad-4796-a8ff-5fa6432f8875.webp"
FACE = "dd91cbb2-f9e4-4b94-9f12-2042f27daf0c.webp"
EYES = "a96a34ee-b6af-45fb-97c1-6e987df3a1cf.webp"
EVIL = "00855ec0-e183-4423-8c39-cd3c8aff58eb.webp"  # the user's evil empire ball, 32 x 32 at 32 px a pixel

# id, kind, name, rarity, sheet, box (x0, y0, x1, y1 around the sprite), worn width (px), anchor
#   anchor: "top" = the hat's bottom edge sits on the brow line y=BROW; "eyes" = centred on the
#   eye line; "mouth" = its top on the mouth line; "eye_r" = centred on the right eye; "horns"
# The ball's canvas is 40 x 40 with the 32 x 32 ball at (OX, OY): headroom for hats (Countryball.G).
G = 40
OX, OY = 4, 7
BROW = OY + 12  # a hat's brim sits here, just over the eyes
MAXH = {"top": BROW + 1, "horns": 18, "eyes": 9, "eye_r": 12, "mouth": G - (OY + 18)}
ITEMS = [
    ("hat_combat_helmet", "hat", "Combat Helmet", "common", HATS, (26, 34, 246, 214), 26, "top"),
    ("hat_officer_cap", "hat", "Officer Cap", "rare", HATS, (282, 42, 486, 215), 25, "top"),
    ("hat_sailor_cap", "hat", "Sailor Cap", "common", HATS, (538, 58, 742, 199), 25, "top"),
    ("hat_peacekeeper", "hat", "Peacekeeper Helmet", "rare", HATS, (794, 42, 998, 198), 25, "top"),
    ("hat_boonie", "hat", "Jungle Boonie", "common", HATS, (18, 562, 254, 702), 29, "top"),
    ("hat_side_cap", "hat", "Side Cap", "common", HATS, (298, 566, 486, 715), 24, "top"),
    ("hat_steel_helmet", "hat", "Steel Helmet", "rare", HATS, (530, 550, 750, 702), 28, "top"),
    ("hat_aviator", "hat", "Aviator Cap", "epic", HATS, (786, 530, 998, 750), 27, "top"),
    ("hat_horns", "hat", "Devil Horns", "epic", FACE, (274, 562, 502, 734), 26, "horns"),
    ("beard_full", "beard", "Full Beard", "common", FACE, (26, 74, 254, 254), 18, "mouth"),
    ("beard_goatee", "beard", "Goatee", "common", FACE, (322, 98, 454, 238), 11, "mouth"),
    ("beard_chinstrap", "beard", "Chinstrap", "rare", FACE, (530, 82, 750, 215), 19, "mouth"),
    ("beard_elder", "beard", "Elder Beard", "legendary", FACE, (786, 74, 998, 446), 12, "mouth"),
    ("beard_handlebar", "beard", "Handlebar Moustache", "rare", FACE, (18, 610, 262, 686), 18, "mouth"),
    ("beard_curled", "beard", "Curled Moustache", "rare", FACE, (521, 610, 758, 742), 18, "mouth"),
    ("beard_horseshoe", "beard", "Horseshoe Moustache", "common", FACE, (802, 594, 990, 727), 14, "mouth"),
    ("glasses_shades", "glasses", "Shades", "common", EYES, (26, 98, 238, 182), 22, "eyes"),
    ("glasses_aviators", "glasses", "Aviators", "rare", EYES, (274, 89, 494, 190), 22, "eyes"),
    ("glasses_monocle", "glasses", "Monocle", "epic", EYES, (594, 74, 735, 231), 9, "eye_r"),
    ("glasses_eyepatch", "glasses", "Eye Patch", "rare", EYES, (786, 34, 974, 222), 20, "eye_r"),
    ("glasses_3d", "glasses", "3D Glasses", "common", EYES, (26, 322, 238, 438), 22, "eyes"),
    ("glasses_nerd", "glasses", "Nerd Glasses", "common", EYES, (274, 322, 494, 446), 22, "eyes"),
    ("glasses_vr", "glasses", "VR Headset", "epic", EYES, (538, 290, 750, 446), 22, "eyes"),
    ("glasses_nvg", "glasses", "Night Vision", "legendary", EYES, (786, 290, 998, 446), 22, "eyes"),
]

# more like these: recoloured variants (id, base, name, rarity, recolour)
VARIANTS = [
    ("hat_combat_arctic", "hat_combat_helmet", "Arctic Combat Helmet", "rare", "arctic"),
    ("hat_boonie_desert", "hat_boonie", "Desert Boonie", "common", "desert"),
    ("hat_officer_navy", "hat_officer_cap", "Admiral Cap", "epic", "navy"),
    ("hat_steel_gold", "hat_steel_helmet", "Golden Helmet", "legendary", "gold"),
    ("hat_side_cap_red", "hat_side_cap", "Red Guard Cap", "rare", "crimson"),
    ("hat_horns_gold", "hat_horns", "Golden Horns", "legendary", "gold"),
    ("beard_full_ginger", "beard_full", "Ginger Beard", "rare", "ginger"),
    ("beard_handlebar_gold", "beard_handlebar", "Golden Handlebar", "legendary", "gold"),
    ("beard_curled_white", "beard_curled", "Silver Moustache", "epic", "silver"),
    ("glasses_shades_gold", "glasses_shades", "Golden Shades", "legendary", "gold"),
    ("glasses_aviators_rose", "glasses_aviators", "Rose Aviators", "epic", "crimson"),
    ("glasses_nvg_red", "glasses_nvg", "Thermal Goggles", "epic", "thermal"),
]

CHARS = "abcdefghijklmnpqrstuvwxyz"  # "o" stays the ball's outline in Countryball


def load(name):
    return np.asarray(Image.open(os.path.join(DL, name)).convert("RGB")).astype(float)


def sprite(sheet, box, width, maxh=99):
    """The sprite in `box`, sampled down to `width` px wide: a list of rows of (r, g, b) or None."""
    a = sheet[box[1] : box[3], box[0] : box[2]]
    bg = np.median(sheet[:40, :40].reshape(-1, 3), axis=0)
    # the background is the navy that reaches the crop's border; dark paint it encloses stays
    near = np.abs(a - bg).sum(axis=2) <= 34
    lab, n = ndimage.label(near)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    mask = ~np.isin(lab, list(edge))
    mask = ndimage.binary_opening(mask, iterations=1)
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    a, mask = a[y0:y1, x0:x1], mask[y0:y1, x0:x1]
    cell = (x1 - x0) / width
    if (y1 - y0) / cell > maxh:  # too tall to wear: narrower
        width = max(4, int((x1 - x0) * maxh / (y1 - y0)))
        cell = (x1 - x0) / width
    h = max(1, min(maxh, int(round((y1 - y0) / cell))))
    out = []
    for j in range(h):
        row = []
        for i in range(width):
            ya, yb = int(j * cell), max(int((j + 1) * cell), int(j * cell) + 1)
            xa, xb = int(i * cell), max(int((i + 1) * cell), int(i * cell) + 1)
            m = mask[ya:yb, xa:xb]
            if m.mean() < 0.42:
                row.append(None)
                continue
            px = a[ya:yb, xa:xb][m]
            # the cell's colour: the median of its inner pixels (edges blur in the upscale)
            c = np.median(px, axis=0)
            if c.sum() < 75:  # the outline
                c = np.array([18, 20, 28])
            row.append(tuple(int(v) for v in c))
        out.append(row)
    while out and all(v is None for v in out[0]):
        out.pop(0)
    while out and all(v is None for v in out[-1]):
        out.pop()
    return out


def quantise(rows, k=9):
    """Merge near colours (k-means on the sprite's own colours)."""
    cols = np.array([c for r in rows for c in r if c is not None], dtype=float)
    uniq = np.unique(cols, axis=0)
    k = min(k, len(uniq))
    rng = np.random.default_rng(3)
    cent = uniq[rng.choice(len(uniq), k, replace=False)]
    for _ in range(25):
        d = ((cols[:, None, :] - cent[None, :, :]) ** 2).sum(axis=2)
        lab = d.argmin(axis=1)
        for i in range(k):
            if (lab == i).any():
                cent[i] = cols[lab == i].mean(axis=0)
    out = []
    for r in rows:
        row = []
        for c in r:
            if c is None:
                row.append(None)
            else:
                d = ((cent - np.array(c)) ** 2).sum(axis=1)
                row.append(tuple(int(v) for v in cent[d.argmin()]))
        out.append(row)
    return out


def recolour(rows, how):
    def f(c):
        if c is None or sum(c) < 70:
            return c
        r, g, b = (v / 255 for v in c)
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        if how == "gold":
            h, s, l = 0.12, 0.85, 0.25 + l * 0.7
        elif how == "silver":
            s, l = 0.06, 0.35 + l * 0.6
        elif how == "arctic":
            s, l = s * 0.25, 0.55 + l * 0.42
        elif how == "desert":
            h, s, l = 0.1, 0.42, 0.3 + l * 0.6
        elif how == "navy":
            if s > 0.25 and 0.08 < h < 0.18:  # keep the gold band
                pass
            else:
                h, s = 0.62, 0.55
        elif how == "crimson":
            if not (s > 0.25 and 0.08 < h < 0.18):
                h, s = 0.99, max(s, 0.65)
        elif how == "ginger":
            h, s, l = 0.06, 0.72, 0.2 + l * 0.75
        elif how == "thermal":
            if g > r + 0.15 and g > b:  # the green lenses glow red
                h, s, l = 0.0, 0.95, 0.55
        r, g, b = colorsys.hls_to_rgb(h, min(max(l, 0), 1), min(max(s, 0), 1))
        return (int(r * 255), int(g * 255), int(b * 255))

    return [[f(c) for c in r] for r in rows]


def place(rows, anchor):
    h, w = len(rows), len(rows[0])
    x = (G - w) // 2
    if anchor == "top":
        y = BROW + 1 - h
    elif anchor == "horns":
        y = OY + 10 - h
    elif anchor == "eyes":
        y = OY + 15 - h // 2
    elif anchor == "eye_r":
        x, y = OX + 20 - w // 2, OY + 15 - h // 2
    else:  # mouth
        y = OY + 18
    return x, y


def lua_item(key, rows, x, y):
    pal, idx = {}, {}
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
    pal_s = ", ".join("%s = { %d, %d, %d }" % (ch, *c) for c, ch in idx.items())
    body = "\n".join('\t\t\t"%s",' % s for s in lines)
    return '\t%s = {\n\t\tx = %d,\n\t\ty = %d,\n\t\tpal = { %s },\n\t\trows = {\n%s\n\t\t},\n\t},' % (key, x, y, pal_s, body)


def ball_preview(rows, x, y, scale=8):
    img = Image.new("RGB", (G, G), (24, 34, 60))
    cx, cy = 15.5 + OX, 15.5 + OY
    for py in range(G):
        for px in range(G):
            d = ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5
            if d <= 14.1:
                img.putpixel((px, py), (18, 20, 28) if d > 13.0 else ((255, 255, 255) if py < cy else (220, 40, 50)))
    for ex in (OX + 8, OX + 17):  # the eyes, for scale
        for yy in range(OY + 13, OY + 17):
            for xx in range(ex + 1, ex + 6):
                img.putpixel((xx, yy), (60, 60, 70))
    for j, r in enumerate(rows):
        for i, c in enumerate(r):
            if c is not None and 0 <= x + i < G and 0 <= y + j < G:
                img.putpixel((x + i, y + j), c)
    return img.resize((G * scale, G * scale), Image.NEAREST)  # 320 px


def backdrop():
    im = Image.open(os.path.join(DL, "images.jpg")).convert("L")
    w, h = 256, 144
    im = im.resize((w, h), Image.LANCZOS)
    a = np.asarray(im).astype(float) / 255
    a = np.clip((a - a.min()) / (np.percentile(a, 99.5) - a.min()), 0, 1) ** 0.8  # brighter, full range
    # a stormy blue-grey ramp in 10 steps with a light 4x4 ordered dither: crisp pixel bands
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16 - 0.5
    levels = 10
    t = np.tile(bayer, (h // 4 + 1, w // 4 + 1))[:h, :w]
    q = np.clip(np.floor(a * (levels - 1) + 0.5 + t * 0.45), 0, levels - 1).astype(int)
    ramp = np.array([[7, 8, 13], [14, 16, 24], [22, 25, 36], [32, 36, 50], [44, 49, 66], [58, 64, 84], [76, 82, 104], [98, 104, 126], [124, 130, 150], [156, 162, 180]], dtype=float)
    out = Image.fromarray(ramp[q].astype(np.uint8))
    out.save(os.path.join(OUT, "shop_bg2.png"))
    out.resize((w * 5, h * 5), Image.NEAREST).save(os.path.join(OUT, "shop_bg2_preview.png"))


def icon():
    im = np.asarray(Image.open(os.path.join(DL, "Itemshop icon.webp")).convert("RGB")).astype(float)
    mx, mn = im.max(axis=2), im.min(axis=2)
    # the baked-in checkerboard: light, colourless pixels joined to the border
    grey = (mx - mn < 26) & (mn > 150)
    lab, n = ndimage.label(grey)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    # the holes in the basket show the checkerboard too: every big light-grey area goes
    sizes = ndimage.sum(grey, lab, range(1, n + 1))
    clear = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 120 or (i + 1) in edge])
    S = 48
    cell = 1024 / S
    out = np.zeros((S, S, 4), dtype=np.uint8)
    for j in range(S):
        for i in range(S):
            ya, yb, xa, xb = int(j * cell), int((j + 1) * cell), int(i * cell), int((i + 1) * cell)
            m = ~clear[ya:yb, xa:xb]
            if m.mean() < 0.5:
                continue
            c = np.median(im[ya:yb, xa:xb][m], axis=0)
            if c.max() - c.min() < 30 and c.min() > 60:  # the checkerboard's grey shadow
                continue
            out[j, i, :3] = c
            out[j, i, 3] = 255
    os.makedirs(os.path.join(OUT, "icons"), exist_ok=True)
    Image.fromarray(out, "RGBA").resize((512, 512), Image.NEAREST).save(os.path.join(OUT, "icons", "item_shop_basket.png"))


def empire():
    """The empire's spiked helmet and angry eyes, sampled 1:1 from the user's evil ball (the same
    32 x 32 ball geometry as ours, so it lands at (OX, OY) on the canvas)."""
    im = load(EVIL)
    grid = [[tuple(int(v) for v in np.median(im[32 * j + 8 : 32 * j + 24, 32 * i + 8 : 32 * i + 24].reshape(-1, 3), axis=0)) for i in range(32)] for j in range(32)]
    bg = grid[0][0]

    def near(a, b, t=40):
        return sum(abs(x - y) for x, y in zip(a, b)) < t

    body = grid[18][6]  # the ball's own colour (the flag goes there)
    helmet = []
    for j in range(13):
        helmet.append([None if near(c, bg) or sum(c) < 70 and j < 4 and near(c, (12, 17, 28)) else c for c in grid[j]])
    eyes = []
    for j in range(14, 19):
        row = []
        for i, c in enumerate(grid[j]):
            keep = 4 <= i <= 27 and not near(c, body) and not near(c, bg) and not near(c, (12, 17, 28), 20) and sum(c) < 120 or (4 <= i <= 27 and sum(c) > 500)
            row.append(c if keep else None)
        eyes.append(row)
    return lua_item("helmet", quantise(helmet, 8), OX, OY) + "\n" + lua_item("eyes", quantise(eyes, 3), OX, OY + 14)


def main():
    sheets = {}
    made = {}
    for it in ITEMS:
        key, kind, name, rarity, sheet, box, width, anchor = it
        if sheet not in sheets:
            sheets[sheet] = load(sheet)
        rows = quantise(sprite(sheets[sheet], box, width, MAXH[anchor]))
        made[key] = (rows, anchor)
    for key, base, name, rarity, how in VARIANTS:
        made[key] = (recolour(made[base][0], how), made[base][1])
    chunks, previews = [], []
    for key, (rows, anchor) in made.items():
        x, y = place(rows, anchor)
        chunks.append(lua_item(key, rows, x, y))
        previews.append(ball_preview(rows, x, y))
    names = {it[0]: it for it in ITEMS}
    meta = []
    for it in ITEMS:
        meta.append('\t{ id = "%s", kind = "%s", name = "%s", rarity = "%s" },' % (it[0], it[1], it[2], it[3]))
    for key, base, name, rarity, how in VARIANTS:
        meta.append('\t{ id = "%s", kind = "%s", name = "%s", rarity = "%s" },' % (key, names[base][1], name, rarity))
    src = (
        "--!strict\n"
        "-- GENERATED by tools/build_gear.py from the user's reference sheets (2026-11-08). Do not edit.\n"
        "-- Countryball gear sprites: x / y = where row 1's first pixel lands on the 40 x 40 ball canvas,\n"
        "-- pal = character -> {r, g, b}, rows top to bottom (\".\" = clear).\n"
        "local GearSprites = {}\n\n"
        "GearSprites.items = {\n" + "\n".join(meta) + "\n}\n\n"
        "GearSprites.art = {\n" + "\n".join(chunks) + "\n}\n\n"
        "--- the empire's look (Countryball): the spiked helmet and the angry eyes of the user's evil ball\n"
        "GearSprites.empire = {\n" + empire() + "\n}\n\n"
        "return GearSprites\n"
    )
    with open(LUA, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(src)
    cols = 8
    sheet = Image.new("RGB", (cols * 320, ((len(previews) + cols - 1) // cols) * 320), (24, 34, 60))
    for i, p in enumerate(previews):
        sheet.paste(p, ((i % cols) * 320, (i // cols) * 320))
    sheet.save(os.path.join(OUT, "gear_preview.png"))
    backdrop()
    icon()
    print(len(made), "gear sprites")


if __name__ == "__main__":
    main()
