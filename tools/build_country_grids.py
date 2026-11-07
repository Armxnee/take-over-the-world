"""Real country borders for every map (Take Over the World!, 2026-11-06).

Rasterizes Natural Earth 1:50m admin-0 countries (public domain; data/raw/ne_50m_admin_0_countries) onto
each map's tile grid with the maps' own equirectangular projection (RoWorld's tools/maps/make_maps.py:
the World map starts at 168.3 W and wraps; the continents are windows), and writes
src/shared/Data/CountryGrids/<Module>.luau:

  return { w, h, nations = { {name, flag, x, y}, ... }, runs = base64(RLE of u16 nation index per tile) }

Index 0 = no country (sea, or a country too small for the map: its land joins a neighbour at load time).
Smaller countries are drawn last so they keep their land where borders overlap at this resolution.
"""
import base64, math, os, struct
import shapefile
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHP = os.path.join(ROOT, "data", "raw", "ne_50m_admin_0_countries", "ne_50m_admin_0_countries.shp")
OUT = os.path.join(ROOT, "src", "shared", "Data", "CountryGrids")

WPPD = 2000 / 360.0
MAPS = [
    dict(id="world", module="World", world=True, width=2000, height=1000,
         lon0=-180.0 + 65 / WPPD, lat_top=90.0 - 10 / WPPD, ppd=WPPD, lat_std=0.0, min_tiles=12),
    dict(id="europe", module="Europe", lon0=-25.0, lon1=45.0, lat_top=72.0, lat_bottom=34.0, ppd=33.0, lat_std=52.0, min_tiles=60),
    dict(id="northamerica", module="NorthAmerica", lon0=-170.0, lon1=-50.0, lat_top=75.0, lat_bottom=7.0, ppd=18.0, lat_std=40.0, min_tiles=60),
    dict(id="southamerica", module="SouthAmerica", lon0=-92.0, lon1=-30.0, lat_top=14.0, lat_bottom=-57.0, ppd=20.0, lat_std=-20.0, min_tiles=60),
    dict(id="asia", module="Asia", lon0=25.0, lon1=150.0, lat_top=78.0, lat_bottom=-12.0, ppd=15.0, lat_std=35.0, min_tiles=60),
    dict(id="africa", module="Africa", lon0=-26.0, lon1=58.0, lat_top=38.0, lat_bottom=-36.0, ppd=18.0, lat_std=10.0, min_tiles=60),
]


def flag_code(rec):
    for k in ("ISO_A2_EH", "ISO_A2", "WB_A2"):
        v = str(rec[k]).strip()
        if len(v) == 2 and v.isalpha():
            return v.lower()
    return ""


def countries():
    r = shapefile.Reader(SHP, encoding="utf-8")
    out = []
    for sr in r.iterShapeRecords():
        rec = sr.record.as_dict()
        shp = sr.shape
        parts = list(shp.parts) + [len(shp.points)]
        rings = [shp.points[parts[i]:parts[i + 1]] for i in range(len(parts) - 1)]
        # area (rough, degrees^2) for the drawing order
        area = 0.0
        for ring in rings:
            a = 0.0
            for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
                a += x1 * y2 - x2 * y1
            area += abs(a) / 2
        out.append(dict(name=str(rec["NAME"]), flag=flag_code(rec), rings=rings, area=area,
                        label=(float(rec["LABEL_X"]), float(rec["LABEL_Y"]))))
    out.sort(key=lambda c: -c["area"])
    return out


def build(spec, cs):
    py = spec["ppd"]
    px = spec["ppd"] * math.cos(math.radians(spec["lat_std"]))
    w = spec.get("width") or int(round((spec["lon1"] - spec["lon0"]) * px))
    h = spec.get("height") or int(round((spec["lat_top"] - spec["lat_bottom"]) * py))
    world = spec.get("world", False)
    proj = lambda lon, lat: ((lon - spec["lon0"]) * px, (spec["lat_top"] - lat) * py)
    img = Image.new("I", (w, h), 0)
    draw = ImageDraw.Draw(img)
    for i, c in enumerate(cs, start=1):
        for ring in c["rings"]:
            pts = [proj(lon, lat) for lon, lat in ring]
            offs = (-w, 0, w) if world else (0,)
            for o in offs:
                q = [(x + o, y) for x, y in pts]
                if max(x for x, _ in q) < 0 or min(x for x, _ in q) > w:
                    continue
                if len(q) >= 3:
                    draw.polygon(q, fill=i)
    grid = list(img.getdata())
    counts = {}
    for v in grid:
        if v:
            counts[v] = counts.get(v, 0) + 1
    keep = sorted(i for i, n in counts.items() if n >= spec["min_tiles"])
    remap = {old: new for new, old in enumerate(keep, start=1)}
    nations = []
    sums = {}
    for t, v in enumerate(grid):
        nv = remap.get(v, 0)
        grid[t] = nv
        if nv:
            s = sums.setdefault(nv, [0, 0, 0])
            s[0] += t % w
            s[1] += t // w
            s[2] += 1
    for old in keep:
        c = cs[old - 1]
        idx = remap[old]
        x, y = proj(*c["label"])
        if world:
            x %= w
        x, y = int(x), int(y)
        if not (0 <= x < w and 0 <= y < h) or grid[y * w + x] != idx:
            # label outside the window or on someone else's tile: the nearest own tile to the centroid
            s = sums[idx]
            cx, cy = s[0] / s[2], s[1] / s[2]
            best, bd = None, 1e18
            for t, v in enumerate(grid):
                if v == idx:
                    d = (t % w - cx) ** 2 + (t // w - cy) ** 2
                    if d < bd:
                        best, bd = t, d
            x, y = best % w, best // w
        nations.append((c["name"], c["flag"], x, y))
    # RLE: (u16 value, varint length) pairs
    out = bytearray()
    t = 0
    n = len(grid)
    while t < n:
        v = grid[t]
        run = 1
        while t + run < n and grid[t + run] == v:
            run += 1
        out += struct.pack("<H", v)
        r = run
        while True:
            b = r & 0x7F
            r >>= 7
            out.append(b | (0x80 if r else 0))
            if not r:
                break
        t += run
    return w, h, nations, base64.b64encode(bytes(out)).decode("ascii")


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    cs = countries()
    os.makedirs(OUT, exist_ok=True)
    for spec in MAPS:
        w, h, nations, runs = build(spec, cs)
        lines = [
            "-- GENERATED by tools/build_country_grids.py from Natural Earth 1:50m admin-0 countries (public domain).",
            "-- Do not edit. Country index per tile (RLE, base64): 0 = none; nations[i] = {name, flag, x, y}.",
            "return {",
            "\tw = %d," % w,
            "\th = %d," % h,
            "\tnations = {",
        ]
        for name, flag, x, y in nations:
            lines.append("\t\t{ %s, %s, %d, %d }," % (lua_str(name), lua_str(flag), x, y))
        lines.append("\t},")
        lines.append("\truns = %s," % lua_str(runs))
        lines.append("}")
        path = os.path.join(OUT, spec["module"] + ".luau")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        print(spec["id"], w, h, len(nations), "nations", len(runs), "chars")


if __name__ == "__main__":
    main()
