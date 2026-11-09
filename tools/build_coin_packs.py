"""Coin pack art for the item shop's BUY COINS page (Take Over the World!, 2026-11-08).

After the user's reference (Fortnite's V-Bucks packs): piles of silver coins with cyan rims, bigger for
each pack, drawn as pixel art, with a star where the reference has its V. Also a sheet of soft white
rays (the cards' and the bundles' background, tinted in game). Writes tools/assets_out/coins_<1-4>.png
and tools/assets_out/rays.png; upload them (MCP upload_image) and put the ids in
src/client/UI/ItemShopPanel.luau (COIN_ART, RAYS). Run from the project root: py tools/build_coin_packs.py
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tools", "assets_out")
W, H, UP = 80, 60, 8  # the pixel canvas, drawn up x8

OUTLINE = (38, 48, 59, 255)
EDGE = (90, 102, 114, 255)
SIDE = (154, 166, 178, 255)
SIDE_HI = (195, 204, 213, 255)
FACE = (227, 233, 239, 255)
FACE_SH = (184, 195, 206, 255)
CYAN = (89, 227, 242, 255)
CYAN_DK = (39, 169, 196, 255)
WHITE = (255, 255, 255, 255)
STAR_SH = (140, 153, 166, 255)


def star(cx, cy, r, squash=1.0):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.45
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a) * squash))
    return pts


def ell(d, cx, cy, rx, ry, fill=None, outline=None):
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=fill, outline=outline)


def stack(d, cx, base, n, rx=9, ry=4):
    """A stack of n flat coins, its bottom face centred at (cx, base)."""
    for i in range(n):
        y = base - i * 2
        ell(d, cx, y + 1, rx, ry, fill=EDGE)
        ell(d, cx, y, rx, ry, fill=SIDE)
        # the rim's cyan marks along the side
        for x in range(cx - rx + 1, cx + rx, 3):
            d.point((x, y + ry), fill=CYAN)
    top = base - (n - 1) * 2 - 1
    ell(d, cx, top, rx, ry, fill=FACE)
    ell(d, cx, top, rx - 2, ry - 1, outline=FACE_SH)
    ell(d, cx, top, rx - 1, ry, outline=CYAN)
    d.polygon(star(cx, top, 3.2, 0.5), fill=WHITE, outline=STAR_SH)


def hero(d, cx, cy, r=12):
    """The big coin standing up in front: thick edge, cyan ring, a star."""
    for k in range(4, 0, -1):
        ell(d, cx + k, cy - k // 2, r, r, fill=EDGE if k > 2 else SIDE)
    ell(d, cx, cy, r, r, fill=FACE)
    ell(d, cx, cy, r - 1, r - 1, outline=CYAN)
    ell(d, cx, cy, r - 2, r - 2, outline=CYAN_DK)
    for a in range(0, 360, 30):  # the ring's notches
        x = cx + (r - 1) * math.cos(math.radians(a))
        y = cy + (r - 1) * math.sin(math.radians(a))
        d.point((round(x), round(y)), fill=WHITE)
    ell(d, cx, cy, r - 4, r - 4, fill=FACE_SH)
    ell(d, cx - 1, cy - 1, r - 4, r - 4, fill=FACE)
    d.polygon(star(cx + 0.5, cy + 0.5, r * 0.55), fill=STAR_SH)
    d.polygon(star(cx, cy, r * 0.55), fill=WHITE, outline=STAR_SH)
    d.point((cx - r + 3, cy - r + 5), fill=WHITE)
    d.point((cx - r + 4, cy - r + 4), fill=WHITE)


def loose(d, cx, cy, rx=8, ry=4, tilt=0):
    ell(d, cx, cy + 1, rx, ry, fill=EDGE)
    ell(d, cx, cy, rx, ry, fill=FACE)
    ell(d, cx, cy, rx - 1, ry, outline=CYAN)
    d.polygon(star(cx, cy, 2.8, 0.5), fill=WHITE, outline=STAR_SH)


# (stacks: back to front as (x, base y, coins); hero: (x, y, r) or None; loose: (x, y))
PACKS = [
    {"stacks": [(46, 40, 3), (54, 44, 2)], "hero": (32, 38, 11), "loose": []},
    {"stacks": [(30, 34, 6), (47, 33, 7), (55, 41, 4), (24, 43, 3)], "hero": (41, 40, 12), "loose": [(60, 48)]},
    {"stacks": [(22, 30, 6), (37, 27, 9), (52, 29, 8), (61, 36, 5), (17, 40, 4), (30, 42, 5), (56, 45, 3)], "hero": (40, 42, 13), "loose": [(14, 50), (64, 50)]},
    {
        "stacks": [
            (12, 25, 5), (26, 24, 7), (40, 23, 8), (54, 24, 7), (67, 25, 5),
            (6, 33, 5), (19, 31, 8), (33, 31, 9), (48, 30, 10), (62, 32, 8), (74, 35, 5),
            (12, 44, 5), (27, 44, 6), (55, 44, 6), (69, 46, 4),
        ],
        "hero": (40, 44, 14),
        "loose": [(8, 54), (72, 55), (24, 55)],
    },
]


def outline(img):
    a = np.array(img)
    m = a[..., 3] > 0
    ring = np.zeros_like(m)
    ring[1:, :] |= m[:-1, :]
    ring[:-1, :] |= m[1:, :]
    ring[:, 1:] |= m[:, :-1]
    ring[:, :-1] |= m[:, 1:]
    ring &= ~m
    a[ring] = OUTLINE
    return Image.fromarray(a)


def pack(spec):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x, base, n in sorted(spec["stacks"], key=lambda s: s[1]):
        stack(d, x, base, n)
    for x, y in spec["loose"]:
        loose(d, x, y)
    if spec["hero"]:
        hero(d, *spec["hero"])
    img = outline(img)
    # a soft shadow under the pile
    a = np.array(img)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ys, xs = np.nonzero(a[..., 3])
    sd = ImageDraw.Draw(sh)
    sd.ellipse((xs.min() - 2, ys.max() - 4, xs.max() + 2, ys.max() + 3), fill=(0, 0, 0, 70))
    sh.alpha_composite(img)
    return sh.resize((W * UP, H * UP), Image.NEAREST)


def rays():
    """Soft white rays from below the middle (transparent elsewhere), 300 x 400."""
    w, h = 300, 400
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h * 0.62
    rnd = random.Random(7)
    a = -math.pi
    while a < math.pi:
        span = rnd.uniform(0.05, 0.12)
        r = 900
        d.polygon([(cx, cy), (cx + r * math.cos(a), cy + r * math.sin(a)), (cx + r * math.cos(a + span), cy + r * math.sin(a + span))], fill=rnd.randint(40, 90))
        a += span + rnd.uniform(0.18, 0.4)
    img = img.filter(ImageFilter.GaussianBlur(2))
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(img)
    return out


def main():
    for i, spec in enumerate(PACKS, start=1):
        pack(spec).save(os.path.join(OUT, "coins_%d.png" % i))
    rays().save(os.path.join(OUT, "rays.png"))
    print("ok")


if __name__ == "__main__":
    main()
