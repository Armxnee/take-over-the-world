"""Map thumbnails (Take Over the World!, 2026-11-08: rebuilt for Korea and the World without Antarctica).

Renders a map's terrain bytes (base64(zstd)) in MapSurface.terrain_pixel's palette, fit within 512 px:
tools/assets_out/thumb_<id>.png. Upload them (MCP upload_image) and put the ids in
src/shared/Assets/MapThumbs.luau. Usage: py tools/assets/make_map_thumbs.py <module path> <id> [...]
"""
import base64
import re
import sys

import numpy as np
import zstandard
from PIL import Image

OCEAN = np.array([0x47, 0x85, 0xB5])
SAND = np.array([0xCC, 0xCB, 0x9E])
PLAINS = np.array([0xBE, 0xDC, 0x8A])
HIGHLAND = np.array([0xDC, 0xCB, 0x9E])
MOUNTAIN = np.array([0xE6, 0xE6, 0xE6])


def render(path, out):
    src = open(path, encoding="utf-8").read()
    w = int(re.search(r"width = (\d+)", src).group(1))
    h = int(re.search(r"height = (\d+)", src).group(1))
    terr = re.search(r'terrain = "([^"]*)"', src).group(1)
    tb = np.frombuffer(zstandard.ZstdDecompressor().decompress(base64.b64decode(terr), max_output_size=w * h * 2), np.uint8)
    tb = tb.reshape(h, w).astype(np.int32)
    land = tb >= 128
    shore = (tb & 64) != 0
    mag = tb & 31
    img = np.zeros((h, w, 3), np.int32)
    m = np.minimum(mag, 10)[..., None]
    img[:] = OCEAN - m
    img[~land & shore] = (0.7 * OCEAN + 76.5).astype(np.int32)
    pl = land & ~shore & (mag < 10)
    img[pl] = np.stack([np.full(pl.sum(), PLAINS[0]), PLAINS[1] - 2 * mag[pl], np.full(pl.sum(), PLAINS[2])], 1)
    hi = land & ~shore & (mag >= 10) & (mag < 20)
    img[hi] = HIGHLAND + 2 * (mag[hi] - 10)[:, None]
    mo = land & ~shore & (mag >= 20) & (mag < 31)
    img[mo] = MOUNTAIN + (mag[mo] // 2)[:, None]
    img[land & shore] = SAND
    img = np.clip(img, 0, 255).astype(np.uint8)
    im = Image.fromarray(img)
    s = 512 / max(w, h)
    im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    im.save(out)
    print(out, im.size)


if __name__ == "__main__":
    args = sys.argv[1:]
    for i in range(0, len(args), 2):
        render(args[i], "tools/assets_out/thumb_%s.png" % args[i + 1])
