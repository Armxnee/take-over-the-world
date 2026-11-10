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

    def outline(self, only_outside_ball=False, skip_dark=False):
        """A dark edge around every piece; `skip_dark`: none around dark pieces (black hair is its own edge)."""
        a = self.img.load()
        edge = []
        for y in range(G):
            for x in range(G):
                if a[x, y][3] > 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < G and 0 <= ny < G and a[nx, ny][3] > 0 and a[nx, ny][:3] != OUT and not (skip_dark and sum(a[nx, ny][:3]) < 200):
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


def strands(c, col, y0, y1, x0=0, x1=31, step=3):
    """Lighter hair strands down a beard (pixels of `col` only), so it reads as hair, not a mouth."""
    lite = tuple(min(255, int(q * 1.45 + 26)) for q in col)
    for y in range(y0 + 1, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x + (y // 3)) % step == 0 and c.img.getpixel((x, y))[:3] == col and c.img.getpixel((x, y))[3] > 0:
                c.px(x, y, lite)


def full(c, col, y0=20, x0=7, x1=24, y1=30):
    """A full beard, kept off the ball's sides so its flag still shows (2026-11-09)."""
    fill_ball(c, y0, col, y1, x0, x1)
    strands(c, col, y0 + 1, y1, x0, x1)
    # rounded off at the bottom corners
    for y in range(y1 - 2, y1 + 1):
        for x in (x0, x0 + 1, x1 - 1, x1):
            if (x in (x0, x1)) or y == y1:
                c.img.putpixel((x, y), (0, 0, 0, 0))


def beard_russian(c):
    full(c, (104, 70, 44), x0=6, x1=25)
    c.texture((84, 54, 34), 24, (6, 20, 25, 30), 7)


def beard_ottoman(c):  # a thick black moustache
    col = (30, 26, 26)
    stache(c, 19, 10, 21, col, 2)
    c.rect(9, 20, 10, 22, col)
    c.rect(21, 20, 22, 22, col)


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
    col = (206, 208, 216)
    for y in range(19, 25):
        for x in range(4, 9):
            if inside(x, y, 1.0):
                c.px(x, y, col)
        for x in range(23, 28):
            if inside(x, y, 1.0):
                c.px(x, y, col)
    stache(c, 19, 8, 23, col, 2)


def beard_spanish(c):  # a pointed beard and an upturned moustache
    col = (66, 42, 28)
    stache(c, 19, 10, 21, col, 2)
    c.line([(10, 19), (8, 17)], col, 1)
    c.line([(21, 19), (23, 17)], col, 1)
    c.poly([(11, 22), (20, 22), (16, 29), (15, 29)], col)


def beard_portuguese(c):
    full(c, (46, 34, 28), x0=9, x1=22, y1=27)


def beard_qing(c):  # Fu Manchu: thin, falling past the chin
    col = (26, 24, 26)
    stache(c, 19, 12, 19, col, 1)
    c.rect(11, 19, 11, 28, col)
    c.rect(20, 19, 20, 28, col)


def beard_persian(c):  # a full black beard, cut square
    full(c, (30, 26, 28), x0=8, x1=23, y1=28)
    c.texture((54, 46, 46), 12, (8, 20, 23, 28), 9)


def beard_brazilian(c):  # a great white beard
    full(c, (232, 232, 230), x0=6, x1=25)
    c.texture((200, 200, 200), 24, (6, 20, 25, 30), 11)


def beard_mexican(c):  # a big black moustache
    col = (28, 24, 24)
    stache(c, 19, 9, 22, col, 2)
    c.rect(8, 20, 9, 25, col)
    c.rect(22, 20, 23, 25, col)


def beard_ethiopian(c):  # a short beard along the jaw
    col = (34, 28, 28)
    stache(c, 19, 11, 20, col, 1)
    for y in range(22, 31):
        for x in range(G):
            if inside(x, y, 1.0) and not inside(x, y, 4.0):
                c.px(x, y, col)
    c.rect(12, 26, 19, 28, col)


def beard_byzantine(c):  # long and full
    full(c, (78, 52, 34), x0=8, x1=23)
    c.texture((58, 38, 24), 20, (8, 20, 23, 30), 13)


def beard_roman(c):  # short and trimmed
    col = (96, 66, 40)
    stache(c, 19, 11, 20, col, 1)
    for y in range(21, 31):
        for x in range(G):
            if inside(x, y, 1.0) and not inside(x, y, 3.0):
                c.px(x, y, col)
    c.rect(11, 25, 20, 28, col)


def beard_korean(c):  # a thin long moustache and a thin long goatee
    col = (28, 26, 28)
    stache(c, 19, 11, 20, col, 1)
    c.rect(10, 20, 10, 22, col)
    c.rect(21, 20, 21, 22, col)
    c.rect(15, 23, 16, 29, col)


def beard_swedish(c):  # a blond Viking beard with two braids
    col, d = (226, 188, 92), (180, 140, 60)
    full(c, col, x0=8, x1=23, y1=26)
    c.rect(11, 26, 12, 30, d)
    c.rect(19, 26, 20, 30, d)
    c.texture(d, 14, (8, 20, 23, 26), 15)


def beard_dutch(c):  # Van Dyke
    col = (150, 104, 58)
    stache(c, 19, 10, 21, col, 1)
    c.line([(10, 19), (8, 17)], col, 1)
    c.line([(21, 19), (23, 17)], col, 1)
    c.poly([(13, 23), (18, 23), (16, 28), (15, 28)], col)


# ---------------------------------------------------------------- (2026-11-09) the other real empires
GREEN_G, BLUE_G = (20, 150, 70), (40, 90, 210)


def folds(c, col, step=4, sign=1):
    """Diagonal folds over whatever is drawn so far (a wrapped cloth)."""
    for y in range(G):
        for x in range(G):
            if c.img.getpixel((x, y))[3] > 0 and (x + sign * y) % step == 0:
                c.px(x, y, col)


def band(c, y0, y1, col):
    """A band around the head: the ball's pixels from row y0 to y1."""
    c.dome(y1, col, ytop=y0)


def points(c, xs, ytop, ybase, col):
    """Crown points: a triangle up to `ytop` at each x."""
    for x in xs:
        c.poly([(x - 2, ybase), (x, ytop), (x + 2, ybase)], col)


def hat_mughal(c):  # white pagri with a jewelled sarpech and a white plume
    w, wd = (240, 236, 224), (204, 196, 178)
    c.ell(4, 2, 27, 12, w)
    folds(c, wd, 5, -1)
    c.rect(5, 10, 26, 10, GOLD)
    c.rect(13, 4, 18, 8, GOLD)  # the sarpech
    c.rect(15, 5, 16, 6, GREEN_G)
    c.px(14, 7, RED)
    c.px(17, 7, RED)
    c.line([(17, 4), (21, 0)], WHITE, 1)  # the plume
    c.px(22, 0, WHITE)


def hat_mongol(c):  # a pointed steel helmet with a fur brim and a red tassel
    fur, fur_l = (112, 78, 48), (166, 126, 86)
    c.poly([(15, 1), (16, 1), (25, 9), (6, 9)], STEEL)
    c.poly([(16, 1), (25, 9), (20, 9)], STEEL_D)
    c.line([(15, 2), (11, 8)], STEEL_H, 1)
    c.rect(14, 0, 17, 1, RED)  # the tassel
    c.rect(3, 8, 28, 11, fur)  # the fur brim
    c.texture(fur_l, 26, (3, 8, 28, 11), 21)
    c.rect(4, 12, 6, 14, fur)  # ear flaps
    c.rect(25, 12, 27, 14, fur)


def hat_inca(c):  # the llawt'u: a braided band, the red fringe and two feathers
    band(c, 8, 10, (196, 40, 40))
    for x in range(0, G, 3):
        c.px(x, 9, (240, 200, 60))
        c.px(x + 1, 9, (30, 30, 34))
    c.rect(12, 11, 19, 12, (214, 30, 40))  # the mascapaicha fringe
    for x in range(12, 20, 2):
        c.px(x, 13, (214, 30, 40))
    c.rect(14, 5, 17, 8, GOLD)  # the gold plate
    c.rect(13, 0, 14, 5, (30, 30, 34))  # two feathers, black tipped white
    c.rect(17, 0, 18, 5, (30, 30, 34))
    c.rect(13, 0, 14, 1, WHITE)
    c.rect(17, 0, 18, 1, WHITE)


def hat_mali(c):  # Mansa Musa's gold crown
    c.rect(6, 7, 25, 10, GOLD)
    points(c, (8, 15.5, 23), 1, 7, GOLD)
    c.rect(6, 10, 25, 10, GOLD_D)
    for x, col in ((9, RED), (15, GREEN_G), (16, GREEN_G), (22, RED)):
        c.px(x, 8, col)
        c.px(x, 9, col)


def hat_songhai(c):  # an indigo turban, its tail to the side
    ind, ind_d = (44, 52, 120), (30, 34, 84)
    c.ell(4, 1, 27, 12, ind)
    folds(c, ind_d, 4, 1)
    c.rect(25, 9, 28, 14, ind)  # the tail of the cloth
    c.rect(26, 11, 27, 14, ind_d)
    c.rect(15, 5, 16, 6, (220, 220, 230))  # a silver clasp


def hat_ashanti(c):  # the Asantehene's black crown with gold ornaments
    c.dome(10, (30, 28, 30), (20, 18, 20), ytop=3)
    c.ell(7, 1, 24, 10, (30, 28, 30))
    c.rect(5, 9, 26, 10, GOLD)  # the gold band
    for x in range(8, 24, 4):
        c.rect(x, 5, x + 1, 6, GOLD)  # gold studs
    c.rect(13, 1, 18, 4, GOLD)  # the front ornament
    c.rect(15, 0, 16, 0, GOLD)
    c.px(15, 2, GOLD_D)
    c.px(16, 2, GOLD_D)


def hat_zulu(c):  # a leopard-skin headband and blue crane feathers
    leo, spot = (222, 160, 60), (60, 40, 24)
    band(c, 7, 11, leo)
    for x, y in ((4, 9), (8, 8), (11, 10), (15, 8), (19, 10), (23, 8), (27, 9), (6, 11), (17, 11), (25, 11)):
        c.px(x, y, spot)
    c.rect(20, 0, 21, 7, (150, 170, 196))  # the feather
    c.rect(21, 0, 22, 2, (110, 130, 160))
    c.rect(8, 3, 9, 7, (150, 170, 196))  # a second, shorter
    c.rect(9, 3, 10, 4, (110, 130, 160))


def hat_vietnamese(c):  # the khan van: the emperor's wrapped yellow turban
    y_, yd = (240, 196, 40), (196, 150, 24)
    c.ell(4, 3, 27, 12, y_)
    for y in (5, 7, 9, 11):
        for x in range(G):
            if c.img.getpixel((x, y))[3] > 0:
                c.px(x, y, yd)
    c.rect(14, 6, 17, 8, RED)  # a red jewel on the front


def hat_bulgarian(c):  # the tsar's kamelaukion: red dome, gold bands, pearl pendilia
    c.ell(8, 1, 23, 10, RED)
    c.rect(6, 7, 25, 10, GOLD)
    c.line([(15.5, 1), (15.5, 7)], GOLD, 1)
    c.line([(8, 5), (23, 5)], GOLD, 1)
    for x, col in ((8, GREEN_G), (12, BLUE_G), (19, BLUE_G), (23, GREEN_G)):
        c.rect(x, 8, x + 1, 9, col)
    c.rect(15, 0, 16, 0, GOLD)  # the cross
    for x in (5, 26):
        for y in range(11, 16, 2):
            c.px(x, y, WHITE)


def hat_serbian(c):  # Tsar Dusan's open gold crown, lily-tipped
    c.rect(6, 7, 25, 10, GOLD)
    for x in (7, 12, 19, 24):
        c.rect(x - 1, 3, x + 1, 6, GOLD)
        c.px(x, 2, GOLD)
        c.px(x - 1, 2, GOLD_D)
        c.px(x + 1, 2, GOLD_D)
    c.rect(15, 1, 16, 6, GOLD)  # the middle, taller, with a cross
    c.rect(14, 2, 17, 2, GOLD)
    for x, col in ((9, RED), (15, BLUE_G), (16, BLUE_G), (22, RED)):
        c.px(x, 8, col)
        c.px(x, 9, col)


def hat_timurid(c):  # a white turban wound round a tall red kulah
    c.poly([(12, 8), (15, 0), (16, 0), (19, 8)], RED)  # the kulah
    c.poly([(16, 0), (19, 8), (17, 8)], RED_D)
    w, wd = (238, 234, 222), (200, 192, 176)
    c.ell(4, 5, 27, 12, w)
    for y in range(5, 13):
        for x in range(G):
            p = c.img.getpixel((x, y))
            if p[3] > 0 and p[:3] == w and (x + y) % 4 == 0:
                c.px(x, y, wd)
    c.rect(15, 7, 16, 8, GOLD)


def hat_durrani(c):  # a dark turban with a jewelled aigrette and plume
    t, td = (52, 70, 50), (34, 48, 34)
    c.ell(4, 2, 27, 12, t)
    folds(c, td, 4, -1)
    c.rect(13, 5, 18, 8, GOLD)  # the aigrette
    c.rect(15, 6, 16, 7, RED)
    c.line([(16, 5), (13, 0)], WHITE, 1)  # the plume
    c.px(12, 0, WHITE)


def hat_central_african(c):  # Bokassa's crown: gold, a great diamond, an eagle on top
    c.rect(7, 7, 24, 10, GOLD)
    c.line([(8, 7), (15, 3), (23, 7)], GOLD, 1)
    c.rect(14, 7, 17, 10, (210, 236, 250))  # the diamond
    c.px(15, 8, WHITE)
    c.rect(13, 1, 18, 2, GOLD)  # the eagle: spread wings and a head
    c.rect(11, 0, 12, 1, GOLD)
    c.rect(19, 0, 20, 1, GOLD)
    c.rect(15, 0, 16, 3, GOLD_D)


def hat_haitian(c):  # Faustin I's gold laurel wreath
    leaf, leaf_d = (200, 168, 48), (150, 120, 30)
    band(c, 8, 10, leaf)
    for x in range(3, 29, 2):
        c.px(x, 7 if x % 4 == 1 else 8, leaf)
        c.px(x, 9, leaf_d)
    c.rect(14, 6, 17, 7, RED)  # a red ribbon at the front
    c.px(13, 8, RED)
    c.px(18, 8, RED)


def hat_moroccan(c):  # the sultan's white turban over a red tarbouche
    c.rect(11, 1, 20, 5, RED)
    c.rect(18, 1, 20, 5, RED_D)
    w, wd = (240, 238, 230), (206, 200, 188)
    c.ell(3, 4, 28, 12, w)
    for y in range(4, 13):
        for x in range(G):
            p = c.img.getpixel((x, y))
            if p[3] > 0 and p[:3] == w and (x + y) % 5 == 0:
                c.px(x, y, wd)


def hat_omani(c):  # the massar: a flat wrapped turban in purple, red and cream
    pur, red2, cream = (110, 50, 120), (196, 50, 60), (236, 220, 180)
    c.ell(3, 3, 28, 12, pur)
    c.rect(4, 5, 27, 9, pur)
    for y in range(G):
        for x in range(G):
            if c.img.getpixel((x, y))[3] > 0:
                if (x + y) % 6 in (0, 1):
                    c.px(x, y, red2)
                elif (x - y) % 6 == 0:
                    c.px(x, y, cream)


def hat_burmese(c):  # the Konbaung crown: a tall tiered gold spire
    c.poly([(9, 10), (12, 4), (19, 4), (22, 10)], GOLD)
    c.poly([(12, 4), (14, 1), (17, 1), (19, 4)], GOLD_D)
    c.rect(15, 0, 16, 1, GOLD)
    c.rect(7, 9, 24, 10, GOLD_D)  # the band
    for y in (5, 7):
        c.line([(11, y), (20, y)], (190, 140, 30), 1)
    c.px(15, 8, RED)
    c.px(16, 8, RED)
    c.rect(4, 8, 7, 9, GOLD)  # the side flares
    c.rect(24, 8, 27, 9, GOLD)


def hat_majapahit(c):  # a Javanese gold crown with wing ornaments
    c.rect(8, 6, 23, 10, GOLD)
    c.poly([(11, 6), (15, 0), (16, 0), (20, 6)], GOLD)  # the tall front
    c.px(15, 3, RED)
    c.px(16, 3, RED)
    c.poly([(8, 8), (2, 3), (4, 8)], GOLD_D)  # the wings
    c.poly([(23, 8), (29, 3), (27, 8)], GOLD_D)
    c.rect(8, 10, 23, 10, GOLD_D)


def hat_danish(c):  # Christian IV's black cavalier hat with a white plume
    c.ell(1, 6, 30, 11, BLACK)
    c.ell(9, 1, 22, 9, BLACK)
    c.rect(9, 6, 22, 7, (190, 30, 40))  # a red band with a white cross stripe
    c.rect(14, 6, 15, 7, WHITE)
    c.ell(18, 0, 27, 5, WHITE)  # the plume
    c.ell(22, 2, 29, 7, (226, 226, 230))


def chin(c, col, top=21, half=5, bottom=29, taper=True, cx=15.5):
    """A beard on the chin: `half` px each side at the top, narrowing toward `bottom` when `taper`."""
    for y in range(top, bottom + 1):
        k = (y - top) / max(1, bottom - top)
        h = half * (1 - 0.6 * k) if taper else half
        if y == bottom:
            h = max(1, h - 1.5)  # a rounded tip
        for x in range(G):
            if abs(x + 0.5 - cx) <= h and inside(x, y, 1.0):
                c.px(x, y, col)
    strands(c, col, top, bottom)


def beard_mughal(c):  # moustache and a short trimmed black beard
    col = (30, 26, 28)
    stache(c, 19, 11, 20, col, 2)
    chin(c, col, 21, 6, 27)


def beard_mongol(c):  # a long drooping moustache and a thin goatee
    col = (30, 26, 28)
    stache(c, 19, 11, 20, col, 1)
    c.rect(10, 19, 10, 24, col)
    c.rect(21, 19, 21, 24, col)
    c.rect(15, 23, 16, 27, col)


def beard_inca(c):  # (none: the Sapa Inca wore no beard)
    pass


def beard_mali(c):  # a short black beard
    col = (30, 26, 28)
    stache(c, 19, 12, 19, col, 1)
    chin(c, col, 21, 5, 26, taper=False)


def beard_songhai(c):  # a grey-black beard
    col, d = (70, 66, 66), (40, 38, 40)
    stache(c, 19, 11, 20, d, 1)
    chin(c, col, 21, 5, 28)
    c.texture(d, 10, (10, 21, 21, 28), 31)


def beard_ashanti(c):  # (none)
    pass


def beard_zulu(c):  # (none)
    pass


def beard_vietnamese(c):  # a thin long moustache and a thin long beard
    col = (30, 26, 28)
    stache(c, 19, 12, 19, col, 1)
    c.rect(11, 20, 11, 23, col)
    c.rect(20, 20, 20, 23, col)
    c.rect(15, 23, 16, 30, col)


def beard_bulgarian(c):  # a long pointed dark beard
    col = (62, 42, 30)
    stache(c, 19, 10, 21, col, 2)
    chin(c, col, 21, 6, 30)
    c.texture((44, 30, 22), 10, (10, 21, 21, 30), 33)


def beard_serbian(c):  # a long brown beard parted in two points
    col = (110, 74, 44)
    stache(c, 19, 10, 21, col, 2)
    chin(c, col, 21, 6, 27, taper=False)
    c.rect(11, 28, 13, 30, col)
    c.rect(18, 28, 20, 30, col)


def beard_timurid(c):  # moustache and a narrow black beard
    col = (30, 26, 28)
    stache(c, 19, 10, 21, col, 1)
    c.line([(10, 19), (9, 21)], col, 1)
    c.line([(21, 19), (22, 21)], col, 1)
    chin(c, col, 22, 3, 28)


def beard_durrani(c):  # a full black beard on the chin
    col = (30, 26, 28)
    stache(c, 19, 10, 21, col, 2)
    chin(c, col, 21, 7, 29)


def beard_central_african(c):  # (none: Bokassa was clean-shaven)
    pass


def beard_haitian(c):  # side whiskers and a moustache
    col = (40, 30, 26)
    stache(c, 19, 11, 20, col, 2)
    for y in range(18, 24):
        for x in list(range(4, 7)) + list(range(25, 28)):
            if inside(x, y, 1.0):
                c.px(x, y, col)


def beard_moroccan(c):  # a neat black beard
    col = (30, 26, 28)
    stache(c, 19, 11, 20, col, 1)
    chin(c, col, 21, 6, 27)


def beard_omani(c):  # a neat black beard with grey in it
    col = (36, 32, 34)
    stache(c, 19, 11, 20, col, 1)
    chin(c, col, 21, 6, 27)
    c.texture((120, 116, 116), 8, (10, 21, 21, 27), 37)


def beard_burmese(c):  # a thin moustache
    stache(c, 19, 12, 19, (30, 26, 28), 1)


def beard_majapahit(c):  # a thin upturned moustache
    col = (30, 26, 28)
    stache(c, 19, 11, 20, col, 1)
    c.px(10, 18, col)
    c.px(21, 18, col)


def beard_danish(c):  # Christian IV: an upturned moustache and a small tuft, light brown
    col = (176, 128, 74)
    stache(c, 19, 10, 21, col, 1)
    c.line([(10, 19), (8, 17)], col, 1)
    c.line([(21, 19), (23, 17)], col, 1)
    c.rect(14, 23, 17, 26, col)


KEYS = ["british", "german", "russian", "ottoman", "japanese", "french", "austrian", "spanish", "portuguese",
        "qing", "persian", "brazilian", "mexican", "ethiopian", "byzantine", "roman", "korean", "swedish", "dutch",
        "mughal", "mongol", "inca", "mali", "songhai", "ashanti", "zulu", "vietnamese", "bulgarian", "serbian",
        "timurid", "durrani", "central_african", "haitian", "moroccan", "omani", "burmese", "majapahit", "danish"]


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


# ---------------------------------------------------------------- the in-game look, for the preview
FIDX = "0123456789abcdefghijklmnopqrstuvwxyz"


def empire_flags():
    import re
    src = open(os.path.join(ROOT, "src", "shared", "Data", "FlagData", "Empires.luau"), encoding="utf-8").read()
    out = {}
    for key, data in re.findall(r'\["emp_([a-z_]+)"\] = "([^"]+)"', src):
        hx, ix = data.split("|")
        pal = [tuple(int(hx[j + o:j + o + 2], 16) for o in (0, 2, 4)) for j in range(0, len(hx), 6)]
        out[key] = (pal, ix)
    return out


def eyes_sprite():
    import re
    src = open(os.path.join(ROOT, "src", "shared", "Data", "GearSprites.luau"), encoding="utf-8").read()
    blk = src[src.index("GearSprites.empire = {"):]
    blk = blk[blk.index("eyes = {"):]
    x = int(re.search(r"x = (\d+)", blk).group(1))
    y = int(re.search(r"y = (\d+)", blk).group(1))
    pal = {ch: (int(r), int(g), int(b)) for ch, r, g, b in re.findall(r"(\w) = \{ (\d+), (\d+), (\d+) \}", blk[: blk.index("rows")])}
    rows = re.findall(r'"([^"]+)"', blk[blk.index("rows"): blk.index("}", blk.index("rows = {") + 9)])
    return x, y, pal, rows


_FLAGS = None
_EYES = None


def render_ball(key, look):
    global _FLAGS, _EYES
    if _FLAGS is None:
        _FLAGS, _EYES = empire_flags(), eyes_sprite()
    pal, ix = _FLAGS.get(key, ([(150, 156, 170)], "0" * 600))
    img = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    for y in range(G):
        for x in range(G):
            dx, dy = x - CX, y - CY
            d = math.sqrt(dx * dx + dy * dy)
            if d <= R + 0.5:
                if d > R - 0.6:
                    img.putpixel((x, y), OUT + (255,))
                    continue
                u = min(max((x - (CX - R)) / (2 * R), 0), 0.999)
                v = min(max((y - (CY - R)) / (2 * R), 0), 0.999)
                c = pal[FIDX.index(ix[int(v * 20) * 30 + int(u * 30)])]
                nx, ny = dx / max(d, 1e-6), dy / max(d, 1e-6)
                if (R - d) < 2.4 and (nx * 0.85 - ny * 0.25 > 0.45 or ny > 0.55):
                    c = tuple(int(q * 0.8 + 0.5) for q in c)
                img.putpixel((x, y), c + (255,))
    img.alpha_composite(look[1])
    ex, ey, epal, erows = _EYES
    for j, row in enumerate(erows):
        for i, ch in enumerate(row):
            if ch in epal:
                img.putpixel((ex + i, ey + j), epal[ch] + (255,))
    img.alpha_composite(look[0])
    return img


def main():
    looks = {}
    for k in KEYS:
        h = Canvas()
        globals()["hat_" + k](h)
        h.outline()
        b = Canvas()
        globals()["beard_" + k](b)
        b.clip_ball(1.0)
        b.outline(skip_dark=True)
        b.clip_ball(0.6)
        looks[k] = (h.img, b.img)
    # the module
    parts = []
    for k in KEYS:
        hs, bs = to_sprite(looks[k][0], False), to_sprite(looks[k][1], True)
        beard = "\t\tbeard = %s,\n" % lua_sprite(bs) if bs is not None else ""  # (none: clean-shaven)
        parts.append("\t%s = {\n\t\that = %s,\n%s\t}," % (k, lua_sprite(hs), beard))
    mod = (
        "--!strict\n"
        "-- GENERATED by tools/build_empire_looks.py. Do not edit.\n"
        "-- (Take Over the World!, 2026-11-08) Each historical empire's own hat and facial hair on its\n"
        "-- Countryball (UI/Countryball): by the empire's flag key (Data/Empires.HISTORICAL, \"emp_<key>\"), in\n"
        "-- GearSprites' sprite format (x, y on the 32 x 32 ball, pal, rows). The player's own gear replaces them.\n"
        "return {\n" + "\n".join(parts) + "\n}\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "EmpireLooks.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    # a preview drawn as the game draws it (UI/Countryball.ball_content): the empire's own flag on the
    # ball, its shaded rim, the facial hair, the empire's angry eyes, then the hat; 4x, 10 a row
    S = 4
    cols = 10
    rows_n = (len(KEYS) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (G + 6) * S + 12, rows_n * (G + 6) * S + 12), (24, 30, 50, 255))
    for i, k in enumerate(KEYS):
        ball = render_ball(k, looks[k])
        big = ball.resize((G * S, G * S), Image.NEAREST)
        sheet.alpha_composite(big, (6 + (i % cols) * (G + 6) * S, 6 + (i // cols) * (G + 6) * S))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "empire_looks_preview.png"))
    print("ok", len(KEYS))


if __name__ == "__main__":
    main()
