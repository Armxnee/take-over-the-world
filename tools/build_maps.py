"""Rasterise every playable map from Natural Earth (public domain) into game cells.

Outputs src/shared/Maps/<Module>.luau with RLE terrain + RLE region ids + region names,
and data/<id>_preview.png. Terrain ids: 0 water, 1 plains, 2 highland, 3 mountain,
4 ice (unclaimable), 5 desert. Region names are real countries (admin-0) or, where a
map zooms in, states/provinces (admin-1). AI nations take the name of the region they
spawn in. Run from the project root: py -I tools/build_maps.py [mapId ...]
"""
import math, os, sys, unicodedata
import numpy as np
import shapefile
import shapely
from shapely.geometry import shape
from scipy import ndimage
from PIL import Image

OTHER = r"C:/Users/izzyn/Downloads/CountyBall War game/data/raw/"
LAND = "data/raw/ne_50m_land/ne_50m_land"
ADM0 = "data/raw/ne_50m_admin_0_countries/ne_50m_admin_0_countries"
ADM1 = OTHER + "ne_10m_admin_1_states_provinces/ne_10m_admin_1_states_provinces"
LAKES = OTHER + "ne_50m_lakes/ne_50m_lakes"
REG = OTHER + "ne_10m_geography_regions_polys/ne_10m_geography_regions_polys"

MAPS = {
    "earth": dict(islands=45, module="Earth", lon=(-180, 180), lat=(-56, 76), W=512, adm1=set()),
    "northamerica": dict(islands=30, module="NorthAmerica", lon=(-170, -50), lat=(7, 72), W=448, adm1={"USA", "CAN", "MEX"}),
    "europe": dict(islands=25, module="Europe", lon=(-25, 45), lat=(34, 71), W=448, adm1=set()),
    "africa": dict(islands=25, module="Africa", lon=(-20, 55), lat=(-36, 38), W=384, adm1=set()),
    "korea": dict(islands=14, module="Korea", lon=(124.2, 130.8), lat=(33.1, 43.0), W=256, adm1={"KOR", "PRK"}, only={"KOR", "PRK"}),
}


def ascii_name(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode()
    return s.replace('"', "").replace("\\", "").strip()


def miller(lat):
    return 1.25 * math.log(math.tan(math.pi / 4 + 0.4 * math.radians(lat)))


def inv_miller(y):
    return math.degrees(2.5 * math.atan(math.exp(0.8 * y)) - 5 * math.pi / 8)


def load(path, flt=None, want=None):
    r = shapefile.Reader(path)
    out = []
    for sr in r.iterShapeRecords():
        if flt and not flt(sr.record):
            continue
        g = shape(sr.shape.__geo_interface__)
        out.append((g, want(sr.record) if want else None))
    return out


def mask_of(geoms, lons, lats):
    m = np.zeros(lons.shape, bool)
    for g, _ in geoms:
        minx, miny, maxx, maxy = g.bounds
        if maxx < lons.min() or minx > lons.max() or maxy < lats.min() or miny > lats.max():
            continue
        m |= shapely.contains_xy(g, lons, lats)
    return m


def add_islands(land, count, seed):
    """Small capturable islands (4-12 cells) a few cells off the coast, in open ocean."""
    if count <= 0:
        return land
    H, W = land.shape
    rng = np.random.default_rng(seed)
    water = ~land
    lab, n = ndimage.label(water)
    sizes = ndimage.sum(water, lab, range(1, n + 1))
    ocean = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz >= 400])
    dist = ndimage.distance_transform_edt(water)
    cand = np.argwhere(ocean & (dist >= 4) & (dist <= 14))
    placed = []
    tries = 0
    while len(placed) < count and tries < count * 60 and len(cand):
        tries += 1
        y, x = cand[rng.integers(len(cand))]
        if any((y - py) ** 2 + (x - px) ** 2 < 15 ** 2 for py, px in placed):
            continue
        size = int(rng.integers(4, 13))
        blob = [(int(y), int(x))]
        seen = {blob[0]}
        for _ in range(size * 6):
            if len(blob) >= size:
                break
            by, bx = blob[rng.integers(len(blob))]
            dy, dx = [(0, 1), (0, -1), (1, 0), (-1, 0)][rng.integers(4)]
            ny, nx = by + dy, bx + dx
            if 0 <= ny < H and 0 <= nx < W and (ny, nx) not in seen and ocean[ny, nx] and dist[ny, nx] >= 2:
                seen.add((ny, nx))
                blob.append((ny, nx))
        if len(blob) >= 4:
            for by, bx in blob:
                land[by, bx] = True
            placed.append((y, x))
    print(f"  islands placed: {len(placed)}")
    return land


def rle(flat):
    runs, i, N = [], 0, flat.size
    while i < N:
        j = i
        while j < N and flat[j] == flat[i]:
            j += 1
        runs.append(f"{int(flat[i])}:{np.base_repr(j - i, 36).lower()},")
        i = j
    return "".join(runs)


def build(mid):
    cfg = MAPS[mid]
    (lo0, lo1), (la0, la1), W = cfg["lon"], cfg["lat"], cfg["W"]
    YN, YS = miller(la1), miller(la0)
    H = round(W * (YN - YS) / math.radians(lo1 - lo0))
    lons = lo0 + (np.arange(W) + 0.5) * (lo1 - lo0) / W
    lats = np.array([inv_miller(YN - (y + 0.5) * (YN - YS) / H) for y in range(H)])
    LON, LAT = np.meshgrid(lons, lats)

    land = mask_of(load(LAND), LON, LAT)
    land &= ~mask_of(load(LAKES, lambda r: r["scalerank"] <= 2), LON, LAT)
    if cfg.get("only"):
        land &= mask_of(load(ADM0, lambda r: r["ADM0_A3"] in cfg["only"]), LON, LAT)
    lab, n = ndimage.label(land)
    sizes = ndimage.sum(land, lab, range(1, n + 1))
    for k, s in enumerate(sizes, 1):
        if s < 3:
            land[lab == k] = False

    land = add_islands(land, cfg.get("islands", 0), sum(map(ord, mid)) * 131)
    mtn = mask_of(load(REG, lambda r: r["FEATURECLA"] == "Range/mtn"), LON, LAT) & land
    plat = mask_of(load(REG, lambda r: r["FEATURECLA"] == "Plateau"), LON, LAT) & land
    desert = mask_of(load(REG, lambda r: r["FEATURECLA"] == "Desert"), LON, LAT) & land
    terr = np.zeros((H, W), np.uint8)
    terr[land] = 1
    terr[desert] = 5
    terr[plat] = 2
    terr[mtn] = 2
    terr[ndimage.binary_erosion(mtn, iterations=1)] = 3
    green = land & mask_of(load(ADM0, lambda r: r["ADM0_A3"] == "GRL"), LON, LAT)
    terr[green & ndimage.binary_erosion(land, iterations=2)] = 4

    # regions: admin-1 for listed countries, admin-0 elsewhere; land cells outside any polygon -> nearest
    names, region = ["?"], np.zeros((H, W), np.int32)
    def add(geoms):
        for g, nm in geoms:
            nm = ascii_name(nm)
            if not nm:
                continue
            m = mask_of([(g, None)], LON, LAT) & land & (region == 0)
            if m.any():
                if nm in names:
                    idx = names.index(nm)
                else:
                    names.append(nm)
                    idx = len(names) - 1
                region[m] = idx
    if cfg["adm1"]:
        add(load(ADM1, lambda r: r["adm0_a3"] in cfg["adm1"], lambda r: r["name_en"] or r["name"]))
    add(load(ADM0, lambda r: r["ADM0_A3"] not in cfg["adm1"], lambda r: r["NAME"]))
    # fill unlabeled land from the nearest labeled cell
    if (land & (region == 0)).any():
        idx = ndimage.distance_transform_edt(region == 0, return_distances=False, return_indices=True)
        filled = region[idx[0], idx[1]]
        region = np.where(land & (region == 0), filled, region)
    region[~land] = 0

    os.makedirs("src/shared/Maps", exist_ok=True)
    with open(f"src/shared/Maps/{cfg['module']}.luau", "w", encoding="utf-8") as fh:
        fh.write("--!strict\n-- Generated by tools/build_maps.py from Natural Earth (public domain). Do not edit.\n")
        fh.write(f'return {{ id = "{mid}", w = {W}, h = {H}, lon = {{ {lo0}, {lo1} }}, lat = {{ {la0}, {la1} }},\n')
        fh.write("\tnames = { " + ", ".join(f'"{x}"' for x in names) + " },\n")
        fh.write(f'\trle = "{rle(terr.flatten())}",\n')
        fh.write(f'\tregions = "{rle(region.flatten())}",\n}}\n')
    flat = terr.flatten()
    claim = int(((flat != 0) & (flat != 4)).sum())
    print(f"{mid}: W={W} H={H} claimable={claim} regions={len(names) - 1}")
    pal = {0: (22, 33, 44), 1: (207, 200, 176), 2: (181, 173, 150), 3: (149, 143, 128), 4: (235, 240, 245), 5: (222, 196, 140)}
    img = Image.new("RGB", (W, H))
    img.putdata([pal[int(t)] for t in flat])
    img.save(f"data/{mid}_preview.png")


for mid in (sys.argv[1:] or list(MAPS)):
    build(mid)
