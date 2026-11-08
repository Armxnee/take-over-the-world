"""Takes Antarctica off the World map (Take Over the World!, 2026-11-08, the user's ask).

Every tile of the World map from Antarctica's northern edge down that belongs to no other country
becomes deep ocean (src/shared/Data/Maps/World.luau: base64(zstd(tile bytes)), WorldMap's byte
format); Antarctica leaves the country grid (src/shared/Data/CountryGrids/World.luau: the other
countries' numbers move down one) and its three nations leave the map's nation list; MapList's land
and nation counts follow. Run once from the project root: py tools/remove_antarctica.py
"""
import base64
import os
import re

import numpy as np
import zstandard

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = os.path.join(ROOT, "src", "shared", "Data", "Maps", "World.luau")
GRID = os.path.join(ROOT, "src", "shared", "Data", "CountryGrids", "World.luau")
LIST = os.path.join(ROOT, "src", "shared", "Data", "MapList.luau")
W, H = 2000, 1000
OCEAN_DEEP = 0x20 | 20  # the ocean bit, 20 cells from land (any depth reads as open sea)


def read_runs(s):
    raw = base64.b64decode(s)
    idx = np.zeros(W * H, np.uint16)
    i, t = 0, 0
    while i < len(raw):
        v = raw[i] | (raw[i + 1] << 8)
        i += 2
        run, shift = 0, 0
        while True:
            b = raw[i]
            i += 1
            run |= (b & 0x7F) << shift
            shift += 7
            if b < 0x80:
                break
        idx[t : t + run] = v
        t += run
    return idx


def write_runs(idx):
    out = bytearray()
    i, n = 0, idx.size
    while i < n:
        v = int(idx[i])
        j = i
        while j < n and idx[j] == v:
            j += 1
        run = j - i
        out += bytes([v & 0xFF, v >> 8])
        while True:
            b = run & 0x7F
            run >>= 7
            out.append(b | (0x80 if run else 0))
            if not run:
                break
        i = j
    return base64.b64encode(bytes(out)).decode()


def main():
    grid_src = open(GRID, encoding="utf-8").read()
    names = re.findall(r'\{ "([^"]*)", "([^"]*)", (\d+), (\d+) \}', grid_src)
    ai = [k for k, n in enumerate(names) if n[0] == "Antarctica"]
    assert ai, "Antarctica is already gone"
    ant = ai[0] + 1  # (grid values are 1-based)
    runs = re.search(r'runs = "([^"]*)"', grid_src)
    idx = read_runs(runs.group(1))
    ys = np.nonzero(idx == ant)[0] // W
    top = int(ys.min())
    print("Antarctica rows", top, "..", int(ys.max()), "tiles", int((idx == ant).sum()))
    # the terrain
    map_src = open(MAP, encoding="utf-8").read()
    m = re.search(r'terrain = "([^"]*)"', map_src)
    tb = np.frombuffer(zstandard.ZstdDecompressor().decompress(base64.b64decode(m.group(1)), max_output_size=W * H * 2), np.uint8).copy()
    assert tb.size == W * H
    rows = np.arange(W * H) // W
    other = (idx != 0) & (idx != ant)
    land_before = int(((tb & 0x80) != 0).sum())
    gone = (rows >= top - 2) & ((tb & 0x80) != 0) & ~other
    tb[gone] = OCEAN_DEEP
    tb[(rows >= top - 2) & ((tb & 0x80) == 0)] = OCEAN_DEEP  # (its lakes and shelf water: open sea)
    # the shoreline bit on land left next to the new sea (bit 6)
    land = (tb & 0x80) != 0
    lg = land.reshape(H, W)
    sea = ~lg
    near = np.zeros_like(lg)
    near[:, 1:] |= sea[:, :-1]
    near[:, :-1] |= sea[:, 1:]
    near[1:, :] |= sea[:-1, :]
    near[:-1, :] |= sea[1:, :]
    shore = (lg & near).reshape(-1)
    tb[shore] |= 0x40
    land_after = int(((tb & 0x80) != 0).sum())
    print("land tiles", land_before, "->", land_after, "(removed", int(gone.sum()), ")")
    enc = base64.b64encode(zstandard.ZstdCompressor(level=19).compress(tb.tobytes())).decode()
    map_src = map_src[: m.start(1)] + enc + map_src[m.end(1) :]
    # its nations, and the land count
    old_lt = int(re.search(r"land_tiles = (\d+)", map_src).group(1))
    assert land_before == old_lt, (land_before, old_lt)  # (land_tiles counts the land bit)
    new_lt = land_after
    lines = map_src.split("\n")
    lines = [l for l in lines if not re.search(r'flag = "aq"', l)]
    map_src = "\n".join(lines)
    map_src = re.sub(r"land_tiles = \d+", "land_tiles = %d" % new_lt, map_src, count=1)
    n_nations = len(re.findall(r"\{ name = \"", map_src))
    open(MAP, "w", encoding="utf-8", newline="").write(map_src)
    # the grid: Antarctica out, the numbers after it down one
    idx[idx == ant] = 0
    idx[idx > ant] -= 1
    lines = grid_src.split("\n")
    out = []
    for l in lines:
        if re.search(r'\{ "Antarctica", "aq", \d+, \d+ \},', l):
            continue
        out.append(l)
    grid_src = "\n".join(out)
    grid_src = re.sub(r'runs = "[^"]*"', 'runs = "%s"' % write_runs(idx), grid_src, count=1)
    open(GRID, "w", encoding="utf-8", newline="").write(grid_src)
    # the map list
    ls = open(LIST, encoding="utf-8").read()
    ls = re.sub(r'(id = "world".*?land_tiles = )\d+(, nations = )\d+', lambda mm: mm.group(1) + str(new_lt) + mm.group(2) + str(n_nations), ls, count=1)
    open(LIST, "w", encoding="utf-8", newline="").write(ls)
    print("land_tiles", old_lt, "->", new_lt, "nations", n_nations)


if __name__ == "__main__":
    main()
