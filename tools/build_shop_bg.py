"""The item shop's backdrop, as pixel art (Take Over the World!, 2026-11-07).

An original scene: a dim showroom with a curved panoramic window (a dusk sky, mountains, green
hills and trees outside), a metal floor and, in the middle of the floor, a round platform with the
game's coin on it. Drawn at 384 x 216 and shown with nearest-neighbour scaling (crisp pixels).
Writes tools/assets_out/shop_bg.png (and a 5x preview, shop_bg_preview.png).
"""
import math
import os
import random

from PIL import Image

W, H = 384, 216
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tools", "assets_out")

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def dither(a, b, t, x, y, steps=5):
    """Two colours mixed by t with a 4x4 ordered dither between the quantised steps."""
    t = max(0.0, min(1.0, t))
    q = t * steps
    lo = math.floor(q)
    frac = q - lo
    if frac * 16 > BAYER[y % 4][x % 4]:
        lo += 1
    return lerp(a, b, min(lo, steps) / steps)


def dim(c, k):
    return tuple(int(v * k) for v in c)


def main():
    rnd = random.Random(7)
    im = Image.new("RGB", (W, H))
    px = im.load()
    cx = W / 2

    def win_top(x):
        d = (x - cx) / cx
        return int(22 + 6 * d * d)

    def win_bot(x):
        d = (x - cx) / cx
        return int(128 + 16 * d * d)

    # mountains: two ridges of smoothed noise
    def ridge(seed, base, amp, freq):
        r = random.Random(seed)
        pts = [r.random() for _ in range(64)]
        out = []
        for x in range(W):
            u = x * freq / W * 18
            i = int(u)
            f = u - i
            f = f * f * (3 - 2 * f)
            v = pts[i] * (1 - f) + pts[i + 1] * f
            out.append(int(base - v * amp))
        return out

    far = ridge(3, 78, 34, 0.9)
    near = ridge(11, 96, 20, 1.6)
    hills = ridge(5, 108, 10, 2.4)
    trees = set()
    for _ in range(140):
        trees.add((rnd.randrange(W), rnd.randrange(96, 128)))

    sky_top, sky_low = (52, 46, 92), (128, 104, 150)
    mt_far, mt_near = (88, 78, 124), (70, 66, 100)
    hill, hill_dark = (66, 98, 58), (46, 72, 44)
    ceiling, wall = (20, 18, 28), (28, 26, 38)
    floor_a, floor_b = (40, 38, 54), (22, 20, 30)

    for y in range(H):
        for x in range(W):
            t, b = win_top(x), win_bot(x)
            if y < t:
                c = dither(ceiling, wall, y / max(t, 1), x, y, 4)
            elif y <= b:
                # outside
                if y < far[x]:
                    c = dither(sky_top, sky_low, (y - t) / 70, x, y)
                elif y < near[x]:
                    c = dither(mt_far, sky_low, (far[x] - y + 12) / 40, x, y, 3) if y < far[x] + 3 else mt_far
                elif y < hills[x]:
                    c = mt_near
                else:
                    c = dither(hill, hill_dark, (y - hills[x]) / 30, x, y, 3)
                c = dim(c, 0.78)
            else:
                # the floor: darker toward the bottom, faint reflections of the window
                c = dither(floor_a, floor_b, (y - b) / (H - b), x, y, 5)
            px[x, y] = c

    # trees: little dark blobs on the hills
    for (tx, ty) in trees:
        if ty < hills[tx] + 2 or ty > win_bot(tx) - 2:
            continue
        for dy in range(-3, 1):
            for dx in range(-2, 3):
                if abs(dx) + max(0, -dy - 1) <= 2 and 0 <= tx + dx < W:
                    px[tx + dx, ty + dy] = dim(lerp(hill_dark, (30, 50, 32), 0.5), 0.78)

    # a few far lights in the dusk
    for lx, ly in ((150, 70), (244, 64), (300, 88)):
        px[lx, ly] = (236, 180, 190)

    # glass streaks
    for x0 in (60, 66, 176, 182, 186, 300, 306):
        for y in range(win_top(x0) + 4, win_bot(x0) - 8):
            x = x0 + (y - 30) // 9
            if 0 <= x < W:
                px[x, y] = lerp(px[x, y], (210, 200, 230), 0.18)

    # the window frame: mullions, top and bottom rails
    for mx in (16, 118, 266, 368):
        for y in range(H):
            if win_top(mx) - 2 <= y <= win_bot(mx) + 1:
                for k in range(-1, 2):
                    if 0 <= mx + k < W:
                        px[mx + k, y] = (14, 13, 20) if k != 1 else (44, 40, 56)
    for x in range(W):
        for k, col in ((0, (12, 11, 18)), (1, (34, 32, 46))):
            px[x, win_top(x) - 1 + k] = col
        b = win_bot(x)
        for k, col in ((1, (70, 66, 88)), (2, (110, 104, 132)), (3, (40, 38, 52)), (4, (26, 24, 34))):
            if b + k < H:
                px[x, b + k] = col

    # window light reflected on the floor
    for x in range(W):
        b = win_bot(x) + 5
        for y in range(b, min(H, b + 26)):
            k = 1 - (y - b) / 26
            if (x // 3 + y) % 7 == 0:
                px[x, y] = lerp(px[x, y], (90, 96, 80), 0.25 * k)

    # the platform: rings on the floor, the coin in the middle (seen at an angle: y squashed)
    pcx, pcy = cx, 196
    for y in range(H):
        for x in range(W):
            dx = (x - pcx) / 150
            dy = (y - pcy) / 46
            r = math.sqrt(dx * dx + dy * dy)
            if r < 1.0:
                c = px[x, y]
                if 0.96 < r < 1.0 or 0.7 < r < 0.73:
                    c = (92, 88, 116) if dy < 0 else (64, 60, 82)
                elif r < 0.7:
                    c = dither((48, 46, 62), (30, 28, 40), r / 0.7, x, y, 4)
                elif 0.73 <= r <= 0.96:
                    c = dither((38, 36, 50), (28, 26, 38), (r - 0.73) / 0.23, x, y, 3)
                px[x, y] = c
    # the grille on the ring (like a vent)
    for i in range(6):
        for x in range(244, 262):
            y = 168 + i * 2
            px[x + i, y] = (20, 18, 28)

    # the coin: gold, a thick rim, a raised star
    ccx, ccy, crx, cry = cx, 192, 30, 16
    gold, rim, hi, shade = (250, 196, 56), (176, 112, 22), (255, 236, 150), (214, 150, 34)
    for y in range(int(ccy - cry - 4), int(ccy + cry + 6)):
        for x in range(int(ccx - crx - 2), int(ccx + crx + 3)):
            dx = (x - ccx) / crx
            dyy = (y - ccy) / cry
            r = math.sqrt(dx * dx + dyy * dyy)
            # the coin's edge (its thickness, seen below the face)
            dye = (y - ccy - 4) / cry
            re = math.sqrt(dx * dx + dye * dye)
            if r <= 1.0:
                if r > 0.86:
                    c = rim
                elif r > 0.78:
                    c = hi if dx + dyy < -0.3 else shade
                else:
                    c = dither(hi, gold, (dx + dyy + 1.2) / 2.2, x, y, 4)
                px[x, y] = c
            elif re <= 1.0 and y > ccy:
                px[x, y] = (130, 80, 14) if (x % 3) else (150, 96, 20)
    # the star (five points), squashed like the coin
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = 0.62 if k % 2 == 0 else 0.26
        pts.append((ccx + math.cos(a) * rr * crx, ccy + math.sin(a) * rr * cry))

    def inside(x, y):
        n = len(pts)
        c = False
        j = n - 1
        for i in range(n):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
                c = not c
            j = i
        return c

    for y in range(int(ccy - cry), int(ccy + cry) + 1):
        for x in range(int(ccx - crx), int(ccx + crx) + 1):
            if inside(x + 0.5, y + 0.5):
                px[x, y] = rim if inside(x + 1.5, y + 1.5) else (255, 246, 196)
    # outline the coin
    out = Image.new("RGB", (W, H))
    out.paste(im)
    op = out.load()
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            dx = (x - ccx) / crx
            dyy = (y - ccy) / cry
            dye = (y - ccy - 4) / cry
            inner = math.sqrt(dx * dx + dyy * dyy) <= 1.0 or (math.sqrt(dx * dx + dye * dye) <= 1.0 and y > ccy)
            if not inner:
                for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ddx = (x + ox - ccx) / crx
                    ddy = (y + oy - ccy) / cry
                    dde = (y + oy - ccy - 4) / cry
                    if math.sqrt(ddx * ddx + ddy * ddy) <= 1.0 or (math.sqrt(ddx * ddx + dde * dde) <= 1.0 and y + oy > ccy):
                        op[x, y] = (18, 14, 10)
                        break
    os.makedirs(OUT, exist_ok=True)
    out.save(os.path.join(OUT, "shop_bg.png"))
    out.resize((W * 4, H * 4), Image.NEAREST).save(os.path.join(OUT, "shop_bg_preview.png"))
    print("wrote shop_bg.png")


if __name__ == "__main__":
    main()
