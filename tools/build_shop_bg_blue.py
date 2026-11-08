"""The item shop's backdrop after the user's Fortnite item shop reference (Take Over the World!, 2026-11-08).

A deep blue gradient, a glowing cyan horizon and a perspective grid running to it (original art, drawn
here). Writes tools/assets_out/shop_bg_blue.png (1280 x 720).
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1280, 720
HORIZON = int(H * 0.66)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tools", "assets_out", "shop_bg_blue.png")


def main():
    y = np.linspace(0, 1, H)[:, None]
    top = np.array([14, 22, 96])
    mid = np.array([30, 70, 220])
    low = np.array([10, 26, 110])
    k = np.clip(y / (HORIZON / H), 0, 1)
    sky = top + (mid - top) * (k ** 1.4)
    k2 = np.clip((y - HORIZON / H) / (1 - HORIZON / H), 0, 1)
    ground = mid * (1 - k2) + low * k2
    col = np.where(y <= HORIZON / H, sky, ground)
    img = np.repeat(col[:, None, :], W, axis=1).reshape(H, W, 3)
    # a soft light behind the cards, a little left of centre
    xs = np.linspace(-1, 1, W)[None, :]
    ys = np.linspace(-1, 1, H)[:, None]
    glow = np.exp(-(((xs + 0.15) / 0.9) ** 2 + ((ys + 0.1) / 0.8) ** 2))
    img = img + glow[:, :, None] * np.array([20, 40, 60])
    base = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    # the grid: lines to a vanishing point on the horizon, and rows closing up towards it
    grid = Image.new("RGBA", (W, H), (90, 230, 255, 0))  # (transparent cyan: a blur leaves no dark fringe)
    d = ImageDraw.Draw(grid)
    vx = W * 0.5
    for i in range(-24, 25):
        x0 = vx + i * 120
        d.line([(vx + i * 6, HORIZON), (x0, H)], fill=(90, 230, 255, 110), width=2)
    # rows: closer together towards the horizon (y = horizon + depth / z)
    for z in range(1, 40):
        yy = HORIZON + (H - HORIZON) * 1.15 / z
        if yy < H:
            d.line([(0, yy), (W, yy)], fill=(90, 230, 255, 110), width=2)
    grid = grid.filter(ImageFilter.GaussianBlur(0.6))
    # the horizon: a bright cyan band, blurred
    band = Image.new("RGBA", (W, H), (120, 245, 255, 0))
    db = ImageDraw.Draw(band)
    db.rectangle([0, HORIZON - 3, W, HORIZON + 3], fill=(120, 245, 255, 255))
    band = band.filter(ImageFilter.GaussianBlur(10))
    out = base.convert("RGBA")
    out = Image.alpha_composite(out, grid)
    out = Image.alpha_composite(out, band)
    out = Image.alpha_composite(out, band)
    # darker edges
    vig = np.clip(1 - 0.45 * (xs ** 2 * 0.6 + ys ** 2 * 0.4), 0.4, 1)
    arr = np.asarray(out).astype(float)
    arr[:, :, :3] *= vig[:, :, None]
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGB").save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
