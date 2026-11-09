"""Each historical empire's own hat and facial hair (Take Over the World!, 2026-11-08, the user's ask:
"every empire has their own hat and mustache or beard related to the country").

Drawn in code on the Countryball's 32 x 32 canvas (Countryball.G: the ball centred at 15.5, 15.5,
radius 13.6, its eyes on rows 12-17): a hat over the top of the ball (it may rise above it), facial
hair inside the outline under the eyes. Every piece gets a dark outline. Writes
src/shared/Data/EmpireLooks.luau ({ [flag key] = { hat = sprite, beard = sprite } } in GearSprites'
sprite format: x, y, pal, rows) and tools/assets_out/empire_looks_preview.png.
Run from the project root: py tools/build_empire_looks.py
"""
import math
import os
import random
import string

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = 32
CX, CY, R = 15.5, 15.5, 13.6
OUT = (18, 20, 28)


def inside(x, y, shrink=1.0):
    return (x + 0.5 - CX) ** 2 + (y + 0.5 - CY) ** 2 <= (R - shrink) ** 2


class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (G, G), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def px(self, x, y, c):
        if 0 <= x < G and 0 <= y < G:
            self.img.putpixel((int(x), int(y)), tuple(c) + (255,))

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle((x0, y0, x1, y1), fill=tuple(c) + (255,))

    def ell(self, x0, y0, x1, y1, c):
        self.d.ellipse((x0, y0, x1, y1), fill=tuple(c) + (255,))

    def poly(self, pts, c):
        self.d.polygon(pts, fill=tuple(c) + (255,))

    def line(self, pts, c, w=1):
        self.d.line(pts, fill=tuple(c) + (255,), width=w)

    def dome(self, ybot, c, shade=None, ytop=0):
        """The ball's top, every ball pixel from ytop down to row ybot."""
        for y in range(ytop, ybot + 1):
            for x in range(G):
                if inside(x, y, 0.0):
                    self.px(x, y, c)
        if shade:
            for y in range(ytop, ybot + 1):
                for x in range(G):
                    if inside(x, y, 0.0) and (x - CX) > 4 and (x - CX) ** 2 + (y - CY) ** 2 > (R - 2.6) ** 2:
                        self.px(x, y, shade)

    def clip_ball(self, shrink=1.0):
        for y in range(G):
            for x in range(G):
                if not inside(x, y, shrink):
                    self.img.putpixel((x, y), (0, 0, 0, 0))

    def texture(self, c, n, box, seed):
        rnd = random.Random(seed)
        x0, y0, x1, y1 = box
        for _ in range(n):
            x, y = rnd.randint(x0, x1), rnd.randint(y0, y1)
            if self.img.getpixel((x, y))[3] > 0:
                self.px(x, y, c)

    def outline(self, only_outside_ball=False):
        a = self.img.load()
        edge = []
        for y in range(G):
            for x in range(G):
                if a[x, y][3] > 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < G and 0 <= ny < G and a[nx, ny][3] > 0 and a[nx, ny][:3] != OUT:
                        edge.append((x, y))
                        break
        for x, y in edge:
            if only_outside_ball and inside(x, y, 0.6):
                continue
            a[x, y] = OUT + (255,)


# ---------------------------------------------------------------- the hats
GOLD, GOLD_D = (232, 184, 48), (176, 128, 30)
BLACK, BLACK_H = (34, 34, 40), (70, 70, 82)
RED, RED_D = (196, 32, 40), (140, 20, 28)
STEEL, STEEL_D, STEEL_H = (168, 174, 186), (118, 124, 138), (220, 226, 236)
WHITE = (240, 240, 236)


def hat_british(c):  # bearskin
    c.ell(6, 0, 25, 12, (28, 26, 28))
    c.dome(10, (28, 26, 28))
    c.texture((64, 60, 62), 40, (5, 0, 26, 10), 1)
    c.rect(4, 10, 27, 10, GOLD)  # chain strap


def hat_german(c):  # pickelhaube
    c.dome(9, BLACK, BLACK_H, ytop=3)
    c.rect(5, 3, 26, 9, BLACK)
    c.ell(5, 1, 26, 12, BLACK)
    c.clip_ball(-0.5)
    c.rect(8, 5, 11, 6, BLACK_H)
    c.rect(3, 10, 28, 11, (24, 24, 28))  # visor
    c.rect(14, 5, 17, 9, GOLD)  # the eagle plate
    c.px(15, 6, GOLD_D)
    c.px(16, 6, GOLD_D)
    c.rect(13, 3, 18, 4, GOLD)  # spike base
    c.rect(15, 0, 16, 2, GOLD)  # spike


def hat_russian(c):  # ushanka
    fur, fur_l = (110, 78, 50), (168, 132, 96)
    c.dome(10, fur)
    c.ell(4, 1, 27, 11, fur)
    c.rect(3, 8, 28, 11, fur_l)  # the folded front band
    c.rect(2, 10, 6, 17, fur_l)  # ear flaps
    c.rect(25, 10, 29, 17, fur_l)
    c.texture((92, 64, 40), 25, (4, 1, 27, 7), 3)
    c.texture((140, 106, 74), 18, (2, 8, 29, 17), 4)
    c.rect(14, 8, 17, 10, GOLD)  # the double eagle badge
    c.px(15, 9, RED)


def hat_ottoman(c):  # fez
    c.poly([(9, 1), (22, 1), (24, 10), (7, 10)], RED)
    c.poly([(19, 1), (22, 1), (24, 10), (21, 10)], RED_D)
    c.rect(9, 1, 22, 1, (220, 60, 60))
    c.line([(15, 0), (22, 3), (23, 8)], BLACK, 1)  # the tassel
    c.rect(22, 7, 24, 9, BLACK)


def hat_japanese(c):  # kabuto
    c.dome(9, (44, 44, 56), (30, 30, 40), ytop=2)
    for y in (5, 7):
        for x in range(4, 28):
            if inside(x, y, 0.0):
                c.px(x, y, (90, 90, 108))
    c.rect(1, 9, 30, 11, (60, 40, 40))  # the flared neck guard
    c.rect(1, 9, 30, 9, (150, 40, 40))
    c.line([(9, 0), (15, 6)], GOLD, 2)  # the crescent crest
    c.line([(22, 0), (16, 6)], GOLD, 2)
    c.rect(14, 5, 17, 7, GOLD_D)


def hat_french(c):  # bicorne
    c.ell(0, 1, 31, 15, BLACK)
    c.img = c.img.crop((0, 0, G, 11)).crop((0, 0, G, G))
    c.d = ImageDraw.Draw(c.img)
    c.line([(1, 9), (6, 4), (15, 1), (25, 4), (30, 9)], GOLD, 1)  # the gold edge
    c.ell(21, 3, 26, 8, (0, 50, 160))  # the tricolour cockade
    c.ell(22, 4, 25, 7, WHITE)
    c.ell(23, 5, 24, 6, RED)


def hat_austrian(c):  # shako
    c.rect(8, 0, 23, 9, (30, 30, 34))
    c.rect(8, 0, 23, 1, GOLD)
    c.rect(19, 1, 23, 9, (20, 20, 24))
    c.rect(13, 3, 18, 7, GOLD)  # the double eagle plate
    c.px(15, 4, BLACK)
    c.px(16, 4, BLACK)
    c.rect(5, 9, 26, 10, (24, 24, 28))  # visor
    c.rect(14, 0, 17, 0, WHITE)  # the pompon


def hat_spanish(c):  # conquistador morion
    c.dome(9, STEEL, STEEL_D, ytop=3)
    c.ell(10, 0, 21, 8, STEEL)  # the comb
    c.rect(15, 0, 16, 7, STEEL_H)
    c.rect(1, 9, 30, 10, STEEL_D)  # the brim, curling up at both ends
    c.rect(0, 6, 2, 9, STEEL_D)
    c.rect(29, 6, 31, 9, STEEL_D)
    c.rect(22, 0, 24, 3, RED)  # a plume


def hat_portuguese(c):  # navigator's tricorne
    c.poly([(2, 5), (15, 1), (29, 5), (27, 10), (16, 12), (4, 10)], BLACK)
    c.line([(2, 5), (15, 1), (29, 5)], GOLD, 1)
    c.line([(4, 10), (16, 12), (27, 10)], GOLD, 1)
    c.rect(14, 4, 17, 7, (0, 100, 50))  # a green cockade
    c.px(15, 5, RED)
    c.px(16, 6, RED)


def hat_qing(c):  # the Qing official's hat
    c.ell(2, 3, 29, 14, (28, 28, 32))
    c.img = c.img.crop((0, 0, G, 11)).crop((0, 0, G, G))
    c.d = ImageDraw.Draw(c.img)
    c.ell(7, 1, 24, 9, RED)  # the red silk fringe
    for x in range(8, 24, 2):
        c.line([(15.5, 1), (x, 8)], RED_D, 1)
    c.rect(15, 0, 16, 1, GOLD)  # the finial
    c.rect(14, 2, 17, 2, GOLD_D)


def hat_persian(c):  # turban
    cream, cream_d = (236, 230, 214), (196, 188, 170)
    c.ell(3, 0, 28, 12, cream)
    # (the wraps: diagonal folds, only on the turban itself)
    for y in range(G):
        for x in range(G):
            if c.img.getpixel((x, y))[3] > 0 and (x + y) % 4 == 0:
                c.px(x, y, cream_d)
    c.rect(14, 4, 17, 7, (30, 90, 200))  # the jewel
    c.px(15, 5, (120, 200, 255))
    c.rect(15, 0, 16, 3, WHITE)  # a feather
    c.rect(14, 8, 17, 8, GOLD)


def hat_brazilian(c):  # imperial crown
    c.rect(7, 7, 24, 10, GOLD)
    for x in (9, 15, 21):
        c.rect(x, 8, x + 1, 9, (20, 150, 70))  # green gems
    c.ell(8, 1, 23, 12, (150, 20, 34))  # velvet
    c.rect(7, 7, 24, 10, GOLD)
    for x in (9, 15, 21):
        c.rect(x, 8, x + 1, 9, (20, 150, 70))
    c.line([(8, 7), (15, 2), (23, 7)], GOLD, 1)  # the arches
    c.line([(15.5, 2), (15.5, 7)], GOLD, 1)
    c.rect(15, 0, 16, 1, GOLD)  # the cross
    c.rect(14, 0, 17, 0, GOLD)


def hat_mexican(c):  # sombrero
    straw, straw_d = (226, 186, 98), (178, 138, 62)
    c.ell(0, 6, 31, 12, straw)
    c.ell(1, 9, 30, 12, straw_d)
    c.ell(9, 0, 22, 9, straw)
    c.rect(9, 5, 22, 7, straw)
    c.rect(9, 6, 13, 7, (0, 120, 70))  # the band, green white red
    c.rect(14, 6, 17, 7, WHITE)
    c.rect(18, 6, 22, 7, (200, 30, 40))


def hat_ethiopian(c):  # the Ethiopian imperial crown
    c.ell(7, 0, 24, 14, GOLD)
    c.img = c.img.crop((0, 0, G, 11)).crop((0, 0, G, G))
    c.d = ImageDraw.Draw(c.img)
    c.rect(7, 8, 24, 10, GOLD_D)
    for x, col in ((10, (200, 30, 40)), (15, (20, 140, 60)), (20, (200, 30, 40))):
        c.rect(x, 4, x + 1, 5, col)
    c.rect(15, 0, 16, 2, GOLD_D)
    c.rect(14, 1, 17, 1, GOLD_D)


def hat_byzantine(c):  # the Byzantine crown with its pendilia
    c.ell(8, 1, 23, 10, (110, 40, 130))
    c.rect(6, 6, 25, 10, GOLD)
    for x, col in ((8, RED), (12, (40, 80, 200)), (16, RED), (20, (40, 80, 200))):
        c.rect(x, 7, x + 1, 8, col)
    c.rect(15, 0, 16, 2, GOLD)
    c.rect(14, 1, 17, 1, GOLD)
    for x in (5, 26):
        for y in range(11, 17, 2):
            c.px(x, y, WHITE)


def hat_roman(c):  # the legionary's galea and its red crest
    bronze, bronze_d = (196, 160, 88), (150, 116, 56)
    c.dome(10, bronze, bronze_d, ytop=3)
    c.rect(3, 10, 6, 15, bronze_d)  # cheek guards
    c.rect(25, 10, 28, 15, bronze_d)
    c.rect(3, 9, 28, 10, bronze_d)
    c.rect(11, 0, 20, 4, RED)  # the crest
    for x in range(11, 21, 2):
        c.px(x, 0, RED_D)
        c.px(x + 1, 2, RED_D)


def hat_korean(c):  # gat
    c.ell(0, 7, 31, 11, (40, 40, 46))
    c.rect(10, 1, 21, 8, (26, 26, 30))
    for y in range(2, 8, 2):
        for x in range(11, 21, 2):
            c.px(x, y, (60, 60, 70))
    c.rect(10, 7, 21, 7, (80, 70, 60))


def hat_swedish(c):  # Viking helmet
    c.dome(9, STEEL, STEEL_D, ytop=2)
    c.rect(3, 8, 28, 9, STEEL_D)
    c.rect(15, 9, 16, 12, STEEL_D)  # the nose guard
    bone = (236, 226, 198)
    c.poly([(5, 8), (1, 1), (3, 0), (7, 6)], bone)
    c.poly([(26, 8), (30, 1), (28, 0), (24, 6)], bone)


def hat_dutch(c):  # capotain
    c.poly([(10, 0), (21, 0), (23, 8), (8, 8)], (28, 28, 32))
    c.rect(8, 6, 23, 8, (110, 78, 46))  # band
    c.rect(14, 6, 17, 8, GOLD)  # buckle
    c.rect(15, 7, 16, 7, (110, 78, 46))
    c.rect(2, 9, 29, 10, (22, 22, 26))  # brim


# ---------------------------------------------------------------- the facial hair
def fill_ball(c, y0, col, y1=31, x0=0, x1=31):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if inside(x, y, 1.0):
                c.px(x, y, col)


def mouth(c, y=22, x0=13, x1=18):
    c.rect(x0, y, x1, y, (60, 20, 24))


def stache(c, y, x0, x1, col, thick=2):
    c.rect(x0, y, x1, y + thick - 1, col)


def beard_british(c):  # walrus
    col = (122, 82, 48)
    stache(c, 19, 9, 22, col, 3)
    c.rect(9, 22, 10, 23, col)
    c.rect(21, 22, 22, 23, col)


def beard_german(c):  # Kaiser moustache, upturned
    col = (54, 42, 36)
    stache(c, 19, 11, 20, col, 2)
    c.line([(11, 19), (8, 18), (6, 15)], col, 1)
    c.line([(20, 19), (23, 18), (25, 15)], col, 1)


def full(c, col, y0=19, mouth_y=22, x0=0, x1=31, y1=31):
    fill_ball(c, y0, col, y1, x0, x1)
    mouth(c, mouth_y)


def beard_russian(c):
    full(c, (104, 70, 44))
    c.texture((84, 54, 34), 30, (3, 19, 28, 30), 7)


def beard_ottoman(c):  # a thick black moustache
    col = (30, 26, 26)
    stache(c, 19, 9, 22, col, 3)
    c.rect(8, 21, 9, 23, col)
    c.rect(22, 21, 23, 23, col)


def beard_japanese(c):  # thin moustache and a small goatee
    col = (30, 28, 30)
    stache(c, 19, 11, 20, col, 1)
    c.rect(14, 24, 17, 27, col)


def beard_french(c):  # the imperial: a waxed moustache and a pointed tuft
    col = (90, 62, 40)
    stache(c, 19, 10, 21, col, 1)
    c.line([(10, 19), (6, 18)], col, 1)
    c.line([(21, 19), (25, 18)], col, 1)
    c.poly([(14, 23), (17, 23), (16, 28), (15, 28)], col)


def beard_austrian(c):  # white mutton chops joined by a moustache
    col = (232, 232, 236)
    for y in range(13, 24):
        for x in range(3, 9):
            if inside(x, y, 1.0):
                c.px(x, y, col)
        for x in range(23, 29):
            if inside(x, y, 1.0):
                c.px(x, y, col)
    stache(c, 19, 8, 23, col, 2)


def beard_spanish(c):  # a pointed beard and an upturned moustache
    col = (66, 42, 28)
    stache(c, 19, 10, 21, col, 2)
    c.line([(10, 19), (8, 17)], col, 1)
    c.line([(21, 19), (23, 17)], col, 1)
    c.poly([(11, 22), (20, 22), (16, 29), (15, 29)], col)
    mouth(c, 22, 14, 17)


def beard_portuguese(c):
    full(c, (46, 34, 28), y1=27)


def beard_qing(c):  # Fu Manchu: thin, falling past the chin
    col = (26, 24, 26)
    stache(c, 19, 12, 19, col, 1)
    c.rect(11, 19, 11, 28, col)
    c.rect(20, 19, 20, 28, col)


def beard_persian(c):  # a full black beard, cut square
    full(c, (30, 26, 28), x0=5, x1=26, y1=28)
    c.texture((54, 46, 46), 16, (5, 20, 26, 28), 9)


def beard_brazilian(c):  # a great white beard
    full(c, (232, 232, 230))
    c.texture((200, 200, 200), 30, (3, 19, 28, 30), 11)
    mouth(c, 22)


def beard_mexican(c):  # a big black moustache
    col = (28, 24, 24)
    stache(c, 19, 7, 24, col, 3)
    c.rect(6, 21, 8, 26, col)
    c.rect(23, 21, 25, 26, col)


def beard_ethiopian(c):  # a short beard along the jaw
    col = (34, 28, 28)
    stache(c, 19, 11, 20, col, 1)
    for y in range(22, 31):
        for x in range(G):
            if inside(x, y, 1.0) and not inside(x, y, 4.0):
                c.px(x, y, col)
    c.rect(12, 26, 19, 28, col)


def beard_byzantine(c):  # long and full
    full(c, (78, 52, 34))
    c.texture((58, 38, 24), 30, (3, 19, 28, 30), 13)


def beard_roman(c):  # short and trimmed
    col = (96, 66, 40)
    stache(c, 19, 11, 20, col, 1)
    for y in range(21, 31):
        for x in range(G):
            if inside(x, y, 1.0) and not inside(x, y, 3.0):
                c.px(x, y, col)
    c.rect(11, 25, 20, 28, col)
    mouth(c, 22, 14, 17)


def beard_korean(c):  # a thin long moustache and a thin long goatee
    col = (28, 26, 28)
    stache(c, 19, 11, 20, col, 1)
    c.rect(10, 20, 10, 22, col)
    c.rect(21, 20, 21, 22, col)
    c.rect(15, 23, 16, 29, col)


def beard_swedish(c):  # a blond Viking beard with two braids
    col, d = (226, 188, 92), (180, 140, 60)
    full(c, col, y1=26)
    c.rect(11, 26, 12, 30, d)
    c.rect(19, 26, 20, 30, d)
    c.texture(d, 20, (3, 19, 28, 26), 15)


def beard_dutch(c):  # Van Dyke
    col = (150, 104, 58)
    stache(c, 19, 10, 21, col, 1)
    c.line([(10, 19), (8, 17)], col, 1)
    c.line([(21, 19), (23, 17)], col, 1)
    c.poly([(13, 23), (18, 23), (16, 28), (15, 28)], col)


KEYS = ["british", "german", "russian", "ottoman", "japanese", "french", "austrian", "spanish", "portuguese",
        "qing", "persian", "brazilian", "mexican", "ethiopian", "byzantine", "roman", "korean", "swedish", "dutch"]


def to_sprite(img, ball_only):
    """GearSprites format: x, y, pal, rows (trimmed)."""
    a = img.load()
    pts = [(x, y) for y in range(G) for x in range(G) if a[x, y][3] > 0]
    if not pts:
        return None
    x0 = min(p[0] for p in pts)
    x1 = max(p[0] for p in pts)
    y0 = min(p[1] for p in pts)
    y1 = max(p[1] for p in pts)
    pal = {}
    chars = string.ascii_letters
    rows = []
    for y in range(y0, y1 + 1):
        row = ""
        for x in range(x0, x1 + 1):
            p = a[x, y]
            if p[3] == 0:
                row += "."
                continue
            k = p[:3]
            if k not in pal:
                pal[k] = chars[len(pal)]
            row += pal[k]
        rows.append(row)
    return {"x": x0, "y": y0, "pal": {v: k for k, v in pal.items()}, "rows": rows}


def lua_sprite(sp):
    pal = ", ".join("%s = { %d, %d, %d }" % (ch, *rgb) for ch, rgb in sorted(sp["pal"].items()))
    rows = "\n".join('\t\t\t\t"%s",' % r for r in sp["rows"])
    return "{\n\t\t\tx = %d,\n\t\t\ty = %d,\n\t\t\tpal = { %s },\n\t\t\trows = {\n%s\n\t\t\t},\n\t\t}" % (sp["x"], sp["y"], pal, rows)


def main():
    looks = {}
    for k in KEYS:
        h = Canvas()
        globals()["hat_" + k](h)
        h.outline()
        b = Canvas()
        globals()["beard_" + k](b)
        b.clip_ball(1.0)
        b.outline()
        b.clip_ball(0.6)
        looks[k] = (h.img, b.img)
    # the module
    parts = []
    for k in KEYS:
        hs, bs = to_sprite(looks[k][0], False), to_sprite(looks[k][1], True)
        parts.append("\t%s = {\n\t\that = %s,\n\t\tbeard = %s,\n\t}," % (k, lua_sprite(hs), lua_sprite(bs)))
    mod = (
        "--!strict\n"
        "-- GENERATED by tools/build_empire_looks.py. Do not edit.\n"
        "-- (Take Over the World!, 2026-11-08) Each historical empire's own hat and facial hair on its\n"
        "-- Countryball (UI/Countryball): by the empire's flag key (Data/Empires.HISTORICAL, \"emp_<key>\"), in\n"
        "-- GearSprites' sprite format (x, y on the 32 x 32 ball, pal, rows). The player's own gear replaces them.\n"
        "return {\n" + "\n".join(parts) + "\n}\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "EmpireLooks.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    # a preview: each on a plain red ball with white eyes
    S = 6
    sheet = Image.new("RGBA", (len(KEYS) * (G + 4) * S // 2 + 40, 2 * (G + 12) * S // 2 + 40), (24, 30, 50, 255))
    for i, k in enumerate(KEYS):
        ball = Image.new("RGBA", (G, G), (0, 0, 0, 0))
        for y in range(G):
            for x in range(G):
                if inside(x, y, 0.0):
                    ball.putpixel((x, y), OUT + (255,) if not inside(x, y, 1.0) else (200, 70, 60, 255))
        for ex in (8, 17):
            for y in range(12, 17):
                for x in range(ex, ex + 7):
                    if 1 <= x - ex <= 5:
                        ball.putpixel((x, y), (255, 255, 255, 255))
        ball.alpha_composite(looks[k][1])
        ball.alpha_composite(looks[k][0])
        big = ball.resize((G * S // 2, G * S // 2), Image.NEAREST)
        col, row = i % 10, i // 10
        sheet.alpha_composite(big, (20 + col * (G + 4) * S // 2, 20 + row * (G + 12) * S // 2))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "empire_looks_preview.png"))
    print("ok", len(KEYS))


if __name__ == "__main__":
    main()
