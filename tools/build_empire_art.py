"""Each historical empire's hat and facial hair, redrawn for the Countryball (World Conquest, 2026-11-12).

After the user's improved sheets (Downloads/fc268d47-...webp hats, Downloads/cecbdd5a-...webp
moustaches and beards): the same designs and colours, drawn pixel by pixel for the ball's 32 x 32
canvas so they sit on it (sampling the sheets down blurred them and they floated). The ball is centred
at 15.5, 15.5 with radius 13.6; the empire's angry eyes are on rows 14-18.
  hats   cover the ball's top down to the brim on row 12 (wide hats may stick out past the outline,
         crests and crosses rise to row 0); every piece gets a dark outline, also over the ball
  beards sit under the eyes from row 19, inside the ball's outline; full beards leave an open mouth
Writes src/shared/Data/EmpireLooks.luau ({ [flag key] = { hat, beard } } in GearSprites' sprite
format) and tools/assets_out/empire_looks_preview.png (as the game draws them, 6x).
Run from the project root: py tools/build_empire_art.py
"""
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_empire_looks as L  # noqa: E402  (Canvas, KEYS, render_ball, to_sprite, lua_sprite)

ROOT = L.ROOT
G, CX, CY, R = L.G, L.CX, L.CY, L.R
OUT = L.OUT
BRIM = 12  # a hat's lowest row (the eyes start on row 14)

GOLD, GOLD_L, GOLD_D = (236, 186, 52), (255, 222, 110), (170, 118, 28)
RED = (196, 30, 44)
VELVET = (168, 22, 44)
BLACK, BLACK_L = (34, 34, 40), (74, 74, 88)
WHITE, WHITE_D = (242, 240, 232), (196, 192, 182)
STEEL, STEEL_L = (168, 174, 186), (222, 228, 238)
BLUE, GREEN, PEARL = (40, 96, 210), (36, 150, 72), (250, 246, 236)
MOUTH = (150, 20, 34)


def m(x):
    """The mirror column of x."""
    return 31 - x


def span(y, shrink=0.0):
    """The ball's columns on row y, (x0, x1), or None."""
    xs = [x for x in range(G) if L.inside(x, y, shrink)]
    return (min(xs), max(xs)) if xs else None


def band(c, y0, y1, col, ext=0):
    """Rows y0..y1 across the ball's width (ext more on both sides)."""
    for y in range(y0, y1 + 1):
        s = span(y)
        if s:
            c.rect(s[0] - ext, y, s[1] + ext, y, col)


def dome(c, y0, y1, col):
    band(c, y0, y1, col)


def sym(c, pts, col):
    """A polygon and its mirror."""
    c.poly(pts, col)
    c.poly([(m(x), y) for x, y in pts], col)


def symrect(c, x0, y0, x1, y1, col):
    c.rect(x0, y0, x1, y1, col)
    c.rect(m(x1), y0, m(x0), y1, col)


def shade(c, k=0.8, cut=6.5, light=1.12):
    """Light from the upper left: the right of the piece darker, its upper left a touch lighter."""
    a = c.img.load()
    for y in range(G):
        for x in range(G):
            p = a[x, y]
            if p[3] == 0 or p[:3] == OUT:
                continue
            f = k if x - CX > cut else (light if x - CX < -6 and y < 8 else 1.0)
            if f != 1.0:
                a[x, y] = tuple(int(min(255, v * f)) for v in p[:3]) + (255,)


def strands(c, col, seed, n=40):
    """A few lighter and darker pixels over the hair."""
    rnd = random.Random(seed)
    lo = tuple(int(v * 0.72) for v in col)
    hi = tuple(int(min(255, v * 1.35 + 18)) for v in col)
    a = c.img.load()
    for i in range(n):
        x, y = rnd.randint(2, 29), rnd.randint(15, 30)
        if a[x, y][3] > 0 and a[x, y][:3] == col:
            a[x, y] = (lo if i % 3 else hi) + (255,)


def fur(c, col, rows, seed):
    rnd = random.Random(seed)
    lo, hi = tuple(int(v * 0.72) for v in col), tuple(min(255, int(v * 1.3) + 16) for v in col)
    a = c.img.load()
    for y in range(rows[0], rows[1] + 1):
        for x in range(G):
            if a[x, y][3] and a[x, y][:3] == col and rnd.random() < 0.35:
                a[x, y] = (lo if rnd.random() < 0.6 else hi) + (255,)


# ---------------------------------------------------------------- hat parts
def jewels(c, y, cols, xs=(6, 10, 15, 16, 21, 25)):
    for i, x in enumerate(xs):
        c.px(x, y, cols[i % len(cols)])


def cross(c, col=GOLD, y=0):
    c.rect(15, y, 16, y + 3, col)
    c.rect(14, y + 1, 17, y + 1, col)


def crown(c, velvet=VELVET, gold=GOLD, gem=(RED, BLUE, GREEN), top="cross", pearls=False, arches=True, by=9):
    """A closed imperial crown worn on the head: velvet cap, arches, a jewelled band, a cross."""
    if velvet:
        dome(c, 3, by - 1, velvet)
    band(c, by, BRIM, gold)
    band(c, BRIM, BRIM, GOLD_D)
    jewels(c, by + 1, gem)
    if pearls:
        for x in range(5, 27, 2):
            c.px(x, by, PEARL)
    for x in (3, 8, 22, 27):  # the band's points
        c.rect(x, by - 2, x + 1, by - 1, gold)
    if arches:
        c.line([(5, by - 1), (7, 5), (11, 3), (15, 3)], gold)
        c.line([(m(5), by - 1), (m(7), 5), (m(11), 3), (16, 3)], gold)
        c.rect(15, 3, 16, by - 1, gold)
        if pearls:
            for y in range(4, by, 2):
                c.px(15, y, PEARL)
    if top == "cross":
        c.rect(14, 2, 17, 3, gold)  # the orb
        cross(c, gold, 0)
    elif top == "plumes":
        for x, h, col in ((11, 1, WHITE), (15, 0, (120, 170, 235)), (19, 1, WHITE)):
            c.rect(x, h, x + 1, 4, col)
        c.rect(14, 3, 17, 4, RED)
    elif top == "plume":
        c.poly([(15, 4), (13, 1), (14, 0), (17, 0), (18, 1), (16, 4)], WHITE)
        c.px(17, 0, WHITE_D)
        c.rect(14, 3, 17, 4, RED)


def turban(c, cloth, fold, y0=1):
    """A wrapped turban over the dome, folds running across it."""
    c.ell(3, y0, 28, BRIM + 2, cloth)
    band(c, 7, BRIM, cloth, 1)
    c.img.paste((0, 0, 0, 0), (0, BRIM + 1, G, G))
    for i, y in enumerate(range(y0 + 3, BRIM, 3)):
        c.line([(4, y + 2), (15, y), (27, y + 2 - (i % 2))], fold)


def cap(c, crown_col, band_col, visor=BLACK, badge=GOLD, top=2):
    """A peaked military cap: a crown wider than the head, a coloured band, a black visor."""
    c.ell(3, top, 28, 10, crown_col)
    c.rect(3, 6, 28, 8, crown_col)
    c.rect(4, 8, 27, 10, band_col)
    c.poly([(5, 11), (26, 11), (23, BRIM), (8, BRIM)], visor)
    c.rect(14, 8, 17, 9, badge)
    c.rect(15, 7, 16, 7, badge)


def tricorne(c, body, trim, ck1, ck2):
    c.ell(6, 2, 25, 12, body)
    c.poly([(0, 7), (8, 8), (15, 10), (16, 10), (23, 8), (31, 7), (29, 11), (16, BRIM), (15, BRIM), (2, 11)], body)
    c.line([(1, 7), (8, 8), (15, 10)], trim)
    c.line([(30, 7), (23, 8), (16, 10)], trim)
    c.ell(7, 6, 10, 9, ck1)
    c.px(8, 7, ck2)
    c.rect(10, 3, 12, 4, BLACK_L)


# ---------------------------------------------------------------- hats
def hat_british(c):  # St Edward's crown: red velvet, gold arches, cross
    crown(c, VELVET, gem=(RED, BLUE, GREEN), pearls=True)


def hat_german(c):  # pickelhaube: black leather, gold eagle plate and spike
    c.ell(4, 3, 27, 18, BLACK)
    c.img.paste((0, 0, 0, 0), (0, 11, G, G))
    c.poly([(2, 11), (29, 11), (27, BRIM), (4, BRIM)], (24, 24, 30))  # the visor
    c.rect(13, 5, 18, 9, GOLD)  # the eagle plate
    c.rect(11, 6, 20, 7, GOLD)
    c.px(15, 6, GOLD_D)
    c.px(16, 6, GOLD_D)
    c.rect(15, 8, 16, 9, GOLD_D)
    c.rect(13, 3, 18, 3, GOLD)  # spike base
    c.rect(14, 2, 17, 2, GOLD)
    c.rect(15, 0, 16, 1, GOLD_L)
    c.rect(7, 5, 9, 6, BLACK_L)  # shine


def hat_russian(c):  # the Great Imperial Crown: two gold half-domes, pearls, a cross
    c.ell(4, 2, 15, 16, GOLD)
    c.ell(16, 2, 27, 16, GOLD)
    c.img.paste((0, 0, 0, 0), (0, 10, G, G))
    for x0 in (6, 18):
        for y in range(4, 9, 2):
            c.px(x0 + 2, y, PEARL)
            c.px(x0 + 4, y + 1, PEARL)
    c.rect(15, 3, 16, 9, PEARL)  # the pearl arch between them
    band(c, 9, BRIM, GOLD)
    band(c, BRIM, BRIM, GOLD_D)
    jewels(c, 10, (RED, PEARL, BLUE), (5, 8, 11, 14, 17, 20, 23, 26))
    c.rect(14, 2, 17, 3, (220, 40, 60))  # the spinel under the cross
    c.rect(15, 0, 16, 1, GOLD)
    c.rect(14, 0, 17, 0, GOLD)


def hat_ottoman(c):  # fez with a black tassel
    c.poly([(9, 1), (22, 1), (25, BRIM), (6, BRIM)], (204, 32, 38))
    c.rect(9, 1, 22, 1, (232, 70, 66))
    c.line([(16, 1), (21, 3), (23, 7)], BLACK)
    c.rect(22, 7, 24, 9, BLACK)


def hat_japanese(c):  # khaki officer cap with a red band and gold star
    cap(c, (132, 128, 86), (176, 34, 38))


def hat_french(c):  # Napoleon's bicorne, worn sideways, gold edged, a cockade
    pts = [(0, 11), (3, 7), (8, 4), (13, 2), (18, 2), (23, 4), (28, 7), (31, 11), (31, BRIM), (0, BRIM)]
    c.poly(pts, BLACK)
    c.line([(1, 10), (3, 8), (8, 5), (13, 3), (18, 3), (23, 5), (28, 8), (30, 10)], GOLD)
    c.ell(19, 5, 23, 9, BLUE)
    c.ell(20, 6, 22, 8, WHITE)
    c.px(21, 7, RED)
    c.rect(1, BRIM - 1, 30, BRIM - 1, (24, 24, 30))


def hat_austrian(c):  # the Austrian imperial crown: a gold mitre over red velvet
    crown(c, VELVET, gem=(RED, GREEN, BLUE), pearls=True, arches=False, top=None)
    c.poly([(9, 8), (10, 3), (15, 2), (15, 8)], GOLD)  # the mitre's two gold halves
    c.poly([(22, 8), (21, 3), (16, 2), (16, 8)], GOLD)
    c.px(12, 5, RED)
    c.px(19, 5, RED)
    c.rect(15, 1, 16, 8, PEARL)
    cross(c, GOLD, -2)
    c.rect(14, 0, 17, 1, BLUE)


def hat_spanish(c):  # a conquistador's morion: steel crest and upturned points
    c.ell(5, 3, 26, 16, STEEL)
    c.img.paste((0, 0, 0, 0), (0, 10, G, G))
    c.poly([(13, 4), (14, 0), (17, 0), (18, 4)], STEEL)  # the comb
    c.rect(15, 1, 16, 3, STEEL_L)
    c.poly([(0, 6), (3, 9), (28, 9), (31, 6), (31, 8), (28, 11), (16, BRIM), (15, BRIM), (3, 11), (0, 8)], STEEL)
    c.line([(1, 7), (4, 10), (15, 11), (16, 11), (27, 10), (30, 7)], STEEL_L)
    c.rect(8, 5, 10, 6, STEEL_L)
    for x in (7, 12, 19, 24):
        c.px(x, 9, GOLD)


def hat_portuguese(c):  # red velvet closed crown, green jewels
    crown(c, (150, 18, 34), gem=(GREEN, RED, GREEN))


def hat_qing(c):  # the Qing official's hat: black upturned brim, red fringe, red knob
    dome(c, 3, 9, (200, 34, 34))
    for x in range(5, 28, 3):
        c.line([(15, 3), (x, 9)], (160, 20, 24))
    band(c, 9, BRIM, (28, 28, 34), 1)
    c.rect(4, 9, 27, 9, (60, 60, 70))
    c.rect(14, 1, 17, 3, (220, 40, 40))  # the knob
    c.rect(15, 0, 16, 0, (255, 120, 110))
    c.rect(13, 3, 18, 3, GOLD)


def hat_persian(c):  # the Kiani crown with jewelled aigrette plumes
    crown(c, (150, 20, 40), gem=(RED, GREEN, BLUE, PEARL), top="plumes", pearls=True)


def hat_brazilian(c):  # Pedro II's crown: deep red velvet, gold, a cross
    crown(c, (120, 16, 30), gem=(GREEN, (240, 210, 60), GREEN), pearls=True)


def hat_mexican(c):  # the bicorne edged with white plumes, a Mexican cockade
    hat_french(c)
    ys = [10, 8, 6, 5, 4, 3, 2, 2, 2, 3, 4, 5, 6, 8, 10]
    for i, x in enumerate(range(1, 31, 2)):
        c.rect(x, ys[i] - 1, x + 1, ys[i], WHITE if i % 2 else WHITE_D)
    c.ell(19, 5, 23, 9, GREEN)
    c.ell(20, 6, 22, 8, WHITE)
    c.px(21, 7, RED)


def hat_ethiopian(c):  # Haile Selassie's crown: all gold, jewelled, a cross
    crown(c, (214, 162, 42), gem=(RED, GREEN, BLUE), pearls=True)
    for y in range(4, 9, 2):
        c.px(10, y, RED)
        c.px(21, y, GREEN)


def hat_byzantine(c):  # the stemma: a gold jewelled band, pearl strings hanging at the sides
    dome(c, 3, 6, (186, 30, 44))
    band(c, 6, BRIM, GOLD)
    band(c, BRIM, BRIM, GOLD_D)
    jewels(c, 8, (RED, BLUE, GREEN, RED), (5, 9, 13, 18, 22, 26))
    jewels(c, 10, (PEARL,), tuple(range(4, 28, 2)))
    c.rect(14, 2, 17, 3, GOLD)
    cross(c, GOLD, -1)
    for x in (3, 28):  # the pendilia
        for y in range(BRIM + 1, BRIM + 7, 2):
            c.px(x, y, PEARL)
        c.px(x, BRIM + 7, RED)


def hat_roman(c):  # a laurel wreath around the head
    leaf, leaf_d = (84, 168, 68), (40, 104, 42)
    for x, y in ((4, 11), (4, 9), (5, 7), (7, 5), (9, 4), (12, 3)):
        for px_, s in ((x, 1), (m(x), -1)):
            c.rect(min(px_, px_ - s), y, max(px_, px_ - s), y, leaf)
            c.px(px_ + s, y - 1, leaf)
    c.line([(4, 11), (5, 7), (9, 4), (13, 3)], leaf_d)
    c.line([(m(4), 11), (m(5), 7), (m(9), 4), (m(13), 3)], leaf_d)
    c.rect(14, BRIM - 1, 17, BRIM, GOLD)  # the ribbon at the front


def hat_korean(c):  # the gat: a tall black crown on a wide fine brim
    c.rect(10, 1, 21, 9, (26, 26, 30))
    c.rect(11, 1, 20, 1, (60, 60, 70))
    c.ell(0, 8, 31, 13, (44, 44, 52))
    c.ell(2, 9, 29, 12, (30, 30, 36))
    c.rect(10, 9, 21, 10, (26, 26, 30))
    c.rect(12, 2, 13, 7, (58, 58, 68))


def hat_swedish(c):  # the black tricorne with gold lace and a blue and yellow cockade
    tricorne(c, BLACK, GOLD, (40, 90, 200), (250, 210, 40))


def hat_dutch(c):  # the black tricorne with gold lace and an orange cockade
    tricorne(c, BLACK, GOLD, (240, 120, 30), (255, 190, 90))


def hat_mughal(c):  # a white turban, a ruby in gold and a pink plume
    turban(c, WHITE, WHITE_D)
    c.line([(5, 6), (15, 3), (26, 6)], (226, 160, 180))
    c.rect(14, 5, 17, 7, GOLD)
    c.rect(15, 6, 16, 6, RED)
    c.poly([(17, 5), (20, 0), (22, 0), (19, 6)], (232, 120, 160))
    c.px(21, 1, (255, 190, 210))


def hat_mongol(c):  # a pointed steel helmet with a fur rim and a spike
    c.ell(6, 2, 25, 16, STEEL)
    c.img.paste((0, 0, 0, 0), (0, 10, G, G))
    c.poly([(13, 3), (15, 0), (16, 0), (18, 3)], STEEL)
    c.rect(15, 0, 16, 2, GOLD)
    c.line([(15, 3), (15, 9)], GOLD)
    c.rect(9, 4, 11, 5, STEEL_L)
    band(c, 9, BRIM, (132, 92, 56), 1)
    fur(c, (132, 92, 56), (9, BRIM), 5)


FEATHERS = [(220, 40, 40), (250, 200, 40), (40, 150, 70), (40, 110, 210), (240, 130, 30)]


def hat_inca(c):  # the mascapaicha: a gold band under a fan of bright feathers
    for i, x in enumerate(range(3, 29, 2)):
        top = 1 + abs(x - 15) // 3
        c.rect(x, top, x + 1, 9, FEATHERS[i % 5])
        c.px(x, top, WHITE)
    band(c, 9, BRIM, GOLD)
    band(c, BRIM, BRIM, GOLD_D)
    c.rect(14, 9, 17, 11, RED)
    c.rect(15, 10, 16, 10, (255, 120, 100))


def hat_mali(c):  # Mansa Musa's tiered gold crown
    for i, y in enumerate(range(2, 10, 2)):
        w = 3 + i * 3
        c.rect(15 - w, y, 16 + w, y + 1, GOLD if i % 2 == 0 else GOLD_D)
    band(c, 9, BRIM, GOLD)
    jewels(c, 10, (RED, GREEN))
    band(c, BRIM, BRIM, GOLD_D)
    c.rect(15, 0, 16, 1, GOLD_L)


def hat_songhai(c):  # a woven conical straw hat with leather trim
    straw, straw_d, leather = (206, 168, 104), (166, 126, 70), (110, 66, 36)
    c.poly([(5, 10), (15, 0), (16, 0), (26, 10)], straw)
    for y in range(2, 10, 2):
        c.line([(15 - y, y + 1), (16 + y, y + 1)], straw_d)
    c.poly([(0, 10), (31, 10), (29, BRIM), (2, BRIM)], straw)
    c.rect(1, BRIM, 30, BRIM, leather)
    c.rect(5, 9, 26, 9, leather)
    c.rect(15, 0, 16, 1, leather)


def hat_ashanti(c):  # a gold headband with two upright gold ornaments
    band(c, 10, BRIM, GOLD)
    band(c, BRIM, BRIM, GOLD_D)
    jewels(c, 11, (GOLD_L, RED), tuple(range(5, 27, 3)))
    for x in (8, 22):
        c.rect(x, 5, x + 1, 9, GOLD)
        c.ell(x - 1, 2, x + 2, 5, GOLD)
        c.px(x, 3, GOLD_L)
    c.rect(14, 6, 17, 9, GOLD)
    c.rect(15, 7, 16, 8, RED)


def hat_zulu(c):  # a feathered headdress: white, black and brown plumes on a beaded band
    cols = [WHITE, (30, 30, 34), (150, 100, 56), WHITE, (30, 30, 34)]
    for i, x in enumerate(range(3, 29, 2)):
        top = 2 + abs(x - 15) // 4
        c.rect(x, top, x + 1, 9, cols[i % 5])
    band(c, 9, BRIM, (164, 112, 60))
    jewels(c, 10, (WHITE, RED, (40, 40, 44)), tuple(range(4, 28, 2)))
    band(c, BRIM, BRIM, (110, 70, 36))


def hat_vietnamese(c):  # the red khan van with gold trim and a gold medallion
    band(c, 3, BRIM, (196, 36, 40), 1)
    band(c, 5, 5, GOLD, 1)
    band(c, 11, BRIM, GOLD, 1)
    c.ell(13, 6, 18, 10, GOLD)
    c.rect(15, 8, 16, 8, RED)
    c.rect(6, 7, 8, 8, (230, 80, 70))


def hat_bulgarian(c):  # a closed gold crown with green jewels
    crown(c, (206, 156, 40), gem=(GREEN, RED, GREEN), pearls=True)


def hat_serbian(c):  # the Nemanjic crown: red velvet, gold, pearls
    crown(c, (176, 26, 40), gem=(RED, BLUE, PEARL), pearls=True)


def hat_timurid(c):  # a red crown under a white plume
    crown(c, (160, 24, 40), gem=(RED, GREEN, BLUE), top="plume")


def hat_durrani(c):  # a white turban with a ruby and a tall pink plume
    turban(c, WHITE, WHITE_D)
    c.poly([(14, 5), (13, 1), (15, 0), (17, 0), (18, 1), (17, 5)], (226, 90, 150))
    c.px(15, 1, (250, 160, 200))
    c.rect(14, 5, 17, 8, GOLD)
    c.rect(15, 6, 16, 7, RED)


def hat_central_african(c):  # Bokassa's green cap with a tall plume
    cap(c, (52, 112, 60), GOLD, badge=GOLD_L, top=3)
    c.poly([(15, 6), (13, 2), (15, 0), (17, 0), (18, 2), (16, 6)], (240, 140, 40))
    c.px(15, 1, (255, 200, 120))


def hat_haitian(c):  # Faustin I's crown: dark blue velvet, gold, a cross
    crown(c, (30, 44, 110), gem=(RED, GREEN, BLUE), pearls=True)


def hat_moroccan(c):  # a red and white checked keffiyeh under a black agal
    a, b = WHITE, (200, 40, 50)
    band(c, 2, BRIM, a, 1)
    for y in range(2, BRIM + 1):
        for x in range(G):
            if c.img.getpixel((x, y))[3] and (x + y) % 3 == 0:
                c.px(x, y, b)
    for x0, x1 in ((1, 3), (28, 30)):  # the cloth falls down the sides
        for y in range(BRIM, BRIM + 9):
            for x in range(x0, x1 + 1):
                c.px(x, y, b if (x + y) % 3 == 0 else a)
    band(c, 7, 8, (26, 26, 30), 1)


def hat_omani(c):  # a striped turban in red, green and gold
    turban(c, (190, 40, 46), (40, 120, 70))
    for y in range(3, BRIM, 3):
        c.line([(4, y + 1), (15, y - 1), (27, y + 1)], (230, 190, 70))


def hat_burmese(c):  # the Konbaung crown: a tall tiered gold spire
    dome(c, 4, BRIM, GOLD)
    for i, y in enumerate(range(0, 9, 2)):
        w = 1 + i * 2
        c.rect(15 - w, y, 16 + w, y + 1, GOLD if i % 2 else GOLD_D)
    band(c, 9, BRIM, GOLD)
    jewels(c, 10, (RED, GREEN, RED), (5, 9, 13, 18, 22, 26))
    band(c, BRIM, BRIM, GOLD_D)
    c.rect(15, 0, 16, 0, RED)


def hat_majapahit(c):  # a Javanese gold helmet crown over black, a spike on top
    dome(c, 4, 9, (40, 40, 48))
    c.line([(5, 9), (8, 5), (15, 3)], GOLD)
    c.line([(26, 9), (23, 5), (16, 3)], GOLD)
    c.rect(15, 3, 16, 9, GOLD)
    band(c, 9, BRIM, GOLD)
    jewels(c, 10, (RED, GREEN))
    band(c, BRIM, BRIM, GOLD_D)
    c.poly([(13, 4), (15, 0), (16, 0), (18, 4)], GOLD)
    c.px(15, 2, RED)


def hat_danish(c):  # Christian V's crown: red velvet, gold, pearls, a cross
    crown(c, (180, 24, 40), gem=(BLUE, RED, GREEN), pearls=True)


# ---------------------------------------------------------------- facial hair
def mustache(c, col, style, y=19):
    if style == "walrus":  # big and bushy, drooping
        c.poly([(8, y + 2), (10, y), (21, y), (23, y + 2), (23, y + 4), (19, y + 2), (12, y + 2), (8, y + 4)], col)
    elif style == "kaiser":  # the upturned "W"
        sym(c, [(15, y + 1), (11, y), (8, y - 2), (6, y - 3), (7, y - 1), (10, y + 2), (15, y + 2)], col)
    elif style == "handlebar":  # curled up at the ends
        sym(c, [(15, y), (11, y), (9, y + 1), (8, y), (7, y - 2), (6, y - 1), (7, y + 1), (10, y + 2), (15, y + 2)], col)
    elif style == "bushy":  # a thick straight moustache
        sym(c, [(15, y), (9, y), (8, y + 2), (10, y + 3), (15, y + 2)], col)
    elif style == "thin":  # a pencil moustache
        symrect(c, 10, y + 1, 15, y + 1, col)
        symrect(c, 9, y + 2, 9, y + 2, col)
    elif style == "droop":  # long and drooping down past the chin
        symrect(c, 10, y, 15, y + 1, col)
        symrect(c, 9, y + 1, 9, y + 8, col)
        symrect(c, 8, y + 7, 8, y + 9, col)
    elif style == "droop_short":
        symrect(c, 10, y, 15, y + 1, col)
        symrect(c, 9, y + 1, 9, y + 5, col)


def goatee(c, col, y0=24, y1=28, w=2, point=True):
    c.rect(16 - w, y0, 15 + w, y1, col)
    if point:
        c.rect(15, y1 + 1, 16, y1 + 2, col)


def mouth(c):
    c.rect(13, 22, 18, 23, OUT)
    c.rect(14, 22, 17, 22, MOUTH)


def full_beard(c, col, top=17, cheek=True, style="round", tache=None):
    """A beard over the lower ball: up the cheeks beside the eyes, an open mouth under the moustache."""
    for y in range(top, G):
        for x in range(G):
            if not L.inside(x, y, 0.6):
                continue
            edge = abs(x - CX)
            if y < 19 and (edge < 10.5 or not cheek):  # beside the eyes only the sideburns
                continue
            if not cheek and y < 21 and edge > 9:
                continue
            if style == "pointed" and y > 25 and edge > 30 - y:
                continue
            if style == "forked" and y > 26 and (edge > 31 - y or edge < 1):
                continue
            if style == "short" and y > 27 and edge > 6:
                continue
            c.px(x, y, col)
    mustache(c, tache or tuple(int(v * 0.8) for v in col), "bushy")
    mouth(c)


def chops(c, col):
    """Mutton chops joined by a moustache, the chin shaved (Franz Joseph)."""
    for y in range(15, 27):
        for x in range(G):
            if L.inside(x, y, 0.6) and abs(x - CX) > 9.5:
                c.px(x, y, col)
    sym(c, [(15, 19), (9, 19), (6, 21), (6, 24), (10, 21), (15, 21)], col)


def beard_british(c):
    mustache(c, (196, 110, 48), "walrus")


def beard_german(c):
    mustache(c, (30, 30, 34), "kaiser")


def beard_russian(c):
    full_beard(c, (112, 74, 44), top=16)


def beard_ottoman(c):
    mustache(c, (28, 28, 32), "handlebar")
    goatee(c, (28, 28, 32), 24, 27, 1)


def beard_japanese(c):
    mustache(c, (30, 30, 34), "bushy")


def beard_french(c):  # Napoleon III: a waxed moustache and an imperial
    mustache(c, (30, 30, 34), "handlebar")
    goatee(c, (30, 30, 34), 23, 27, 1)


def beard_austrian(c):
    chops(c, (128, 86, 52))


def beard_spanish(c):
    mustache(c, (96, 60, 36), "handlebar")
    goatee(c, (96, 60, 36), 23, 27, 2)


def beard_portuguese(c):
    mustache(c, (30, 30, 34), "bushy")
    goatee(c, (30, 30, 34), 24, 27, 1)


def beard_qing(c):
    mustache(c, (26, 26, 30), "droop")


def beard_persian(c):
    full_beard(c, (34, 36, 52), top=16)


def beard_brazilian(c):
    full_beard(c, (118, 78, 46), top=16)


def beard_mexican(c):
    mustache(c, (28, 28, 32), "handlebar")


def beard_ethiopian(c):
    full_beard(c, (30, 30, 34), style="short")


def beard_byzantine(c):
    full_beard(c, (30, 30, 34), style="pointed")


def beard_roman(c):
    full_beard(c, (104, 66, 40), style="short", cheek=False)


def beard_korean(c):
    mustache(c, (26, 26, 30), "thin")
    goatee(c, (26, 26, 30), 24, 26, 1, point=False)


def beard_swedish(c):
    full_beard(c, (150, 98, 54), top=16)


def beard_dutch(c):
    mustache(c, (30, 30, 34), "handlebar")
    goatee(c, (30, 30, 34), 24, 26, 1, point=False)


def beard_mughal(c):  # a moustache and a beard along the jaw, the chin's middle trimmed
    full_beard(c, (30, 30, 34), style="short")
    a = c.img.load()
    for y in range(24, 27):
        for x in range(12, 20):
            a[x, y] = (0, 0, 0, 0)
    mouth(c)


def beard_mongol(c):
    mustache(c, (30, 30, 34), "droop_short")
    goatee(c, (30, 30, 34), 24, 27, 1)


def beard_inca(c):
    full_beard(c, (110, 72, 44), style="short", cheek=False)


def beard_mali(c):
    full_beard(c, (40, 32, 30))


def beard_songhai(c):
    full_beard(c, (36, 36, 42), style="pointed")


def beard_ashanti(c):
    full_beard(c, (30, 30, 34), style="short")


def beard_zulu(c):
    full_beard(c, (30, 30, 34), cheek=False)


def beard_vietnamese(c):
    mustache(c, (30, 30, 34), "droop_short")
    goatee(c, (30, 30, 34), 24, 29, 1)


def beard_bulgarian(c):
    full_beard(c, (70, 46, 32), style="pointed")


def beard_serbian(c):
    full_beard(c, (98, 62, 38), style="forked")


def beard_timurid(c):
    full_beard(c, (28, 28, 32), top=16)


def beard_durrani(c):
    full_beard(c, (30, 30, 34))


def beard_central_african(c):
    full_beard(c, (30, 30, 34), style="short", cheek=False)


def beard_haitian(c):
    full_beard(c, (30, 30, 34))


def beard_moroccan(c):
    full_beard(c, (30, 30, 34), style="short")


def beard_omani(c):
    full_beard(c, (34, 34, 38), style="pointed")


def beard_burmese(c):
    mustache(c, (30, 30, 34), "thin")
    goatee(c, (30, 30, 34), 24, 26, 1)


def beard_majapahit(c):
    mustache(c, (30, 30, 34), "handlebar")
    goatee(c, (30, 30, 34), 25, 26, 1, point=False)


def beard_danish(c):
    full_beard(c, (176, 128, 72), tache=(150, 104, 56))


# ---------------------------------------------------------------- build
HANGS = ("moroccan", "byzantine")  # hats that hang below the brim, down the sides


def make(k):
    h = L.Canvas()
    globals()["hat_" + k](h)
    if k not in HANGS:
        h.img.paste((0, 0, 0, 0), (0, BRIM + 1, G, G))
    shade(h)
    h.outline()
    b = L.Canvas()
    globals()["beard_" + k](b)
    b.clip_ball(1.0)
    col = next((p[:3] for p in b.img.getdata() if p[3] and p[:3] not in (OUT, MOUTH)), None)
    if col is not None:
        strands(b, col, len(k))
    b.outline(skip_dark=True)
    b.clip_ball(0.6)
    return h.img, b.img


def main():
    looks = {k: make(k) for k in L.KEYS}
    parts = []
    for k in L.KEYS:
        hs, bs = L.to_sprite(looks[k][0], False), L.to_sprite(looks[k][1], True)
        assert len(hs["pal"]) <= 52 and len(bs["pal"]) <= 52, k
        parts.append("\t%s = {\n\t\that = %s,\n\t\tbeard = %s,\n\t}," % (k, L.lua_sprite(hs), L.lua_sprite(bs)))
    mod = (
        "--!strict\n"
        "-- GENERATED by tools/build_empire_art.py (the user's empire hat and beard sheets, redrawn for the\n"
        "-- 32 x 32 ball). Do not edit.\n"
        "-- (World Conquest, 2026-11-12) Each historical empire's own hat and facial hair on its Countryball\n"
        "-- (UI/Countryball): by the empire's flag key (Data/Empires.HISTORICAL, \"emp_<key>\"), in GearSprites'\n"
        "-- sprite format (x, y on the 32 x 32 ball, pal, rows). The player's own gear replaces them.\n"
        "return {\n" + "\n".join(parts) + "\n}\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "EmpireLooks.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    S, cols = 6, 10
    rows_n = (len(L.KEYS) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (G + 6) * S + 12, rows_n * (G + 6) * S + 12), (24, 30, 50, 255))
    for i, k in enumerate(L.KEYS):
        big = L.render_ball(k, looks[k]).resize((G * S, G * S), Image.NEAREST)
        sheet.alpha_composite(big, (6 + (i % cols) * (G + 6) * S, 6 + (i // cols) * (G + 6) * S))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "empire_looks_preview.png"))
    print("ok", len(L.KEYS))


if __name__ == "__main__":
    main()
