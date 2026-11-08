"""The Korean War map (Take Over the World!, 2026-11-08): all of North and South Korea, big.

From Natural Earth 1:10m admin-1 provinces (public domain): the land of KOR and PRK only (the rest of
the window is sea), each province a country (South Korea's under the "kr" flag, North Korea's under
"kp"), relief from the 1:10m mountain and plateau regions plus the distance from the coast.
Writes, in the formats of tools/maps/make_maps.py and tools/build_country_grids.py:
  src/server/MapData/Korea.luau          id, name, nations, codec "zstd+base64", terrain (tile bytes)
  src/shared/Data/CountryGrids/Korea.luau  w, h, nations {name, flag, x, y}, runs
  src/shared/Data/MapList.luau            the "korea" row
Tile byte (WorldMap.luau): bit 7 land, bit 6 shoreline, bit 5 ocean, bits 0-4 magnitude (land
elevation 0-30, water min(ceil(dist / 2), 31)). Run from the project root: py tools/build_korea.py
"""
import base64
import math
import os
import re
import struct
import unicodedata

import numpy as np
import shapefile
import shapely
import zstandard
from PIL import Image
from scipy import ndimage
from shapely.geometry import shape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OTHER = r"C:/Users/izzyn/Downloads/CountyBall War game/data/raw/"
ADM1 = OTHER + "ne_10m_admin_1_states_provinces/ne_10m_admin_1_states_provinces"
REG = OTHER + "ne_10m_geography_regions_polys/ne_10m_geography_regions_polys"

LON0, LON1 = 124.0, 131.0
LAT_BOTTOM, LAT_TOP = 33.0, 43.1
LAT_STD = 38.0
PPD = 132  # tiles per degree of latitude: about 1,330 tall, 730 wide
FLAG = {"KOR": "kr", "PRK": "kp"}


def ascii_name(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode()
    return s.replace('"', "").replace("\\", "").strip()


def main():
    px = PPD * math.cos(math.radians(LAT_STD))
    W = int(round((LON1 - LON0) * px))
    H = int(round((LAT_TOP - LAT_BOTTOM) * PPD))
    lons = LON0 + (np.arange(W) + 0.5) / px
    lats = LAT_TOP - (np.arange(H) + 0.5) / PPD
    LON, LAT = np.meshgrid(lons, lats)
    print("size", W, "x", H)
    # the provinces
    r = shapefile.Reader(ADM1)
    provs = []
    for sr in r.iterShapeRecords():
        rec = sr.record.as_dict()
        a3 = rec.get("adm0_a3") or rec.get("ADM0_A3")
        if a3 not in FLAG:
            continue
        name = ascii_name(rec.get("name_en") or rec.get("name") or "")
        provs.append((shape(sr.shape.__geo_interface__), name, FLAG[a3]))
    provs.sort(key=lambda p: (p[2], p[1]))
    grid = np.zeros((H, W), np.uint16)
    for i, (g, name, flag) in enumerate(provs, start=1):
        minx, miny, maxx, maxy = g.bounds
        sel = (LON >= minx) & (LON <= maxx) & (LAT >= miny) & (LAT <= maxy)
        if not sel.any():
            continue
        inside = shapely.contains_xy(g, LON[sel], LAT[sel])
        sub = grid[sel]
        sub[inside & (sub == 0)] = i
        grid[sel] = sub
    # specks under a few tiles: sea
    land = grid > 0
    lab, n = ndimage.label(land)
    sizes = ndimage.sum(land, lab, range(1, n + 1))
    for k, s in enumerate(sizes, 1):
        if s < 6:
            grid[lab == k] = 0
    land = grid > 0
    # keep provinces with land; renumber
    counts = np.bincount(grid.ravel(), minlength=len(provs) + 1)
    keep = [i for i in range(1, len(provs) + 1) if counts[i] >= 200]
    remap = np.zeros(len(provs) + 1, np.uint16)
    for new, old in enumerate(keep, start=1):
        remap[old] = new
    grid = remap[grid]
    land = grid > 0
    # relief: mountains and plateaus, and height away from the coast
    def region_mask(cla):
        rr = shapefile.Reader(REG)
        m = np.zeros((H, W), bool)
        for sr in rr.iterShapeRecords():
            rec = sr.record.as_dict()
            if (rec.get("FEATURECLA") or rec.get("featurecla")) != cla:
                continue
            g = shape(sr.shape.__geo_interface__)
            minx, miny, maxx, maxy = g.bounds
            if maxx < LON0 or minx > LON1 or maxy < LAT_BOTTOM or miny > LAT_TOP:
                continue
            m |= shapely.contains_xy(g, LON, LAT)
        return m

    mtn = region_mask("Range/mtn") & land
    plat = region_mask("Plateau") & land
    dist_in = ndimage.distance_transform_edt(land)
    rng = np.random.default_rng(1950)
    noise = ndimage.gaussian_filter(rng.random((H, W)), 6)
    noise = (noise - noise.min()) / (noise.max() - noise.min() + 1e-9)
    elev = np.clip(dist_in / 14.0, 0, 9) + noise * 4
    elev = np.where(plat, 12 + noise * 6, elev)
    elev = np.where(mtn, 6 + noise * 18 + ndimage.gaussian_filter(rng.random((H, W)), 2) * 4, elev)  # (highland with peaks, not one white sheet)
    elev = np.clip(np.round(elev), 0, 30).astype(np.uint8)
    # water: distance to land
    sea = ~land
    dist_out = ndimage.distance_transform_edt(sea)
    wmag = np.clip(np.ceil(dist_out / 2.0), 1, 31).astype(np.uint8)
    tb = np.where(land, 0x80 | elev, 0x20 | wmag).astype(np.uint8)
    near = np.zeros_like(land)
    near[:, 1:] |= sea[:, :-1]
    near[:, :-1] |= sea[:, 1:]
    near[1:, :] |= sea[:-1, :]
    near[:-1, :] |= sea[1:, :]
    tb[land & near] |= 0x40
    land_tiles = int(land.sum())
    print("land tiles", land_tiles, "provinces", len(keep))
    # each province's label: the own tile nearest its centroid
    nations = []
    for new, old in enumerate(keep, start=1):
        ys, xs = np.nonzero(grid == new)
        cy, cx = ys.mean(), xs.mean()
        k = int(np.argmin((ys - cy) ** 2 + (xs - cx) ** 2))
        g, name, flag = provs[old - 1]
        nations.append((name, flag, int(xs[k]), int(ys[k])))
    # the map module
    terrain = base64.b64encode(zstandard.ZstdCompressor(level=19).compress(tb.tobytes())).decode()
    nat_lines = "\n".join('\t\t{ name = "%s", flag = "%s", x = %d, y = %d },' % n for n in nations)
    mod = (
        "-- GENERATED by tools/build_korea.py from public-domain data (Natural Earth 1:10m). Do not edit.\n"
        "-- terrain = base64(zstd(width * height bytes)), the tile byte format of WorldMap.luau.\n"
        "return {\n"
        '\tid = "korea",\n'
        '\tname = "Korean War",\n'
        '\tmodule = "Korea",\n'
        "\twidth = %d,\n"
        "\theight = %d,\n"
        "\tk_lin = 1.0,\n"
        '\tcategories = { "featured", "war", "asia" },\n'
        "\tmultiplayer_frequency = 0,\n"
        "\tforced_modifiers = {},\n"
        "\tland_tiles = %d,\n"
        "\tnations = {\n%s\n\t},\n"
        '\tcodec = "zstd+base64",\n'
        "\tsize = %d,\n"
        '\tterrain = "%s",\n'
        "}\n"
    ) % (W, H, land_tiles, nat_lines, W * H, terrain)
    open(os.path.join(ROOT, "src", "server", "MapData", "Korea.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    # the country grid
    out = bytearray()
    flat = grid.ravel()
    t, n = 0, flat.size
    while t < n:
        v = int(flat[t])
        j = t
        while j < n and flat[j] == v:
            j += 1
        out += struct.pack("<H", v)
        run = j - t
        while True:
            b = run & 0x7F
            run >>= 7
            out.append(b | (0x80 if run else 0))
            if not run:
                break
        t = j
    gl = "\n".join('\t\t{ "%s", "%s", %d, %d },' % n for n in nations)
    gmod = (
        "-- GENERATED by tools/build_korea.py from Natural Earth 1:10m admin-1 provinces (public domain).\n"
        "-- Do not edit. Country index per tile (RLE, base64): 0 = none; nations[i] = {name, flag, x, y}.\n"
        "return {\n\tw = %d,\n\th = %d,\n\tnations = {\n%s\n\t},\n\truns = \"%s\",\n}\n"
    ) % (W, H, gl, base64.b64encode(bytes(out)).decode())
    open(os.path.join(ROOT, "src", "shared", "Data", "CountryGrids", "Korea.luau"), "w", encoding="utf-8", newline="\n").write(gmod)
    # the map list
    lp = os.path.join(ROOT, "src", "shared", "Data", "MapList.luau")
    ls = open(lp, encoding="utf-8").read()
    row = (
        '\t{ id = "korea", name = "Korean War", module = "Korea", width = %d, height = %d, k_lin = 1.0, '
        'categories = { "featured", "war", "asia" }, multiplayer_frequency = 0, land_tiles = %d, nations = %d },'
    ) % (W, H, land_tiles, len(nations))
    ls = re.sub(r'\t\{ id = "korea".*\n', "", ls)
    ls = ls.replace('\t{ id = "northamerica"', row + '\n\t{ id = "northamerica"', 1)
    open(lp, "w", encoding="utf-8", newline="").write(ls)
    # a preview
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = (20, 40, 90)
    pal = np.array([[0, 0, 0]] + [[int(60 + (i * 37) % 160), int(120 + (i * 53) % 120), int(60 + (i * 29) % 100)] for i in range(1, len(keep) + 1)])
    img[land] = pal[grid[land]]
    img[mtn] = (img[mtn] * 0.6).astype(np.uint8)
    Image.fromarray(img).save(os.path.join(ROOT, "tools", "assets_out", "korea_preview.png"))
    print("nations:", ", ".join(n[0] for n in nations))


if __name__ == "__main__":
    main()
