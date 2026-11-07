"""Icons for the item shop's Robux products (Take Over the World!, 2026-11-07): a pile of gold coins
(coin packs) and an olive supply chest with a gold star (bundles), pixel art at 32 x 32, saved 16x
(512 x 512) to tools/assets_out/icons/product_coins.png and product_bundle.png."""
import os
from PIL import Image, ImageDraw

OUT = os.path.join("tools", "assets_out", "icons")
INK = (18, 14, 10, 255)


def coin(px, cx, cy, r=5):
    for y in range(cy - r - 1, cy + r + 3):
        for x in range(cx - r - 1, cx + r + 2):
            dx, dy = x - cx, y - cy
            face = dx * dx + (dy * 1.6) ** 2 <= r * r
            edge = dx * dx + ((dy - 2) * 1.6) ** 2 <= r * r and dy > 0
            if face:
                px[x, y] = (255, 236, 150, 255) if dx + dy < -2 else (250, 196, 56, 255)
            elif edge:
                px[x, y] = (176, 112, 22, 255)


def outline(im):
    src = im.copy().load()
    px = im.load()
    for y in range(32):
        for x in range(32):
            if src[x, y][3] == 0:
                for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if 0 <= x + ox < 32 and 0 <= y + oy < 32 and src[x + ox, y + oy][3] > 0:
                        px[x, y] = INK
                        break


def coins():
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    px = im.load()
    for cx, cy in ((10, 24), (16, 25), (22, 24), (13, 19), (19, 19), (16, 13)):
        coin(px, cx, cy)
    # a star on the top coin
    for x, y in ((16, 11), (15, 12), (16, 12), (17, 12), (16, 13), (14, 12), (18, 12)):
        px[x, y] = (200, 130, 20, 255)
    outline(im)
    return im


def bundle():
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((4, 12, 27, 27), fill=(110, 122, 58, 255))
    d.rectangle((4, 8, 27, 13), fill=(140, 154, 78, 255))
    d.rectangle((4, 13, 27, 14), fill=(70, 78, 36, 255))
    d.rectangle((14, 8, 17, 27), fill=(214, 218, 228, 255))
    d.rectangle((4, 19, 27, 20), fill=(214, 218, 228, 255))
    star = [(16, 15), (17, 18), (20, 18), (18, 20), (19, 23), (16, 21), (13, 23), (14, 20), (12, 18), (15, 18)]
    d.polygon(star, fill=(250, 196, 56, 255))
    outline(im)
    return im


def save(im, name):
    bg = Image.new("RGBA", (32, 32), (24, 30, 58, 255))
    bg.alpha_composite(im)
    bg.resize((512, 512), Image.NEAREST).save(os.path.join(OUT, name))


os.makedirs(OUT, exist_ok=True)
save(coins(), "product_coins.png")
save(bundle(), "product_bundle.png")
print("ok")
