"""Unit skins and the train from the user's sprite sheets (Take Over the World!, 2026-11-08).

Sheets (C:/Users/izzyn/Downloads, navy background):
  boats     a732129d-...webp  8 cargo ships (bow to the left)
  missiles  cd7ab50d-...webp  8 missiles (nose up)
  nukes     4ae1c86d-...webp  8 bombs (nose up)
  warships  eca17a71-...webp  8 warships (bow to the right)
  train     64602707-...webp  a locomotive (to the left) and container cars
Each sprite is cut out (background off, holes filled), brought down to its pixel-art size (about
4.5 source px a pixel) and saved to tools/assets_out/skins/<name>.png; boats, warships and the train
get a mirrored copy (<name>_r / <name>_l: facing right / left). A few skins are recolours of a
sheet sprite (RECOLOUR). Writes tools/assets_out/skins/manifest.json: name -> {file, w, h}.
After uploading, tools/build_unit_skins.py --ids ids.json writes src/shared/Data/UnitSkins.luau.
Run from the project root: py tools/build_unit_skins.py
"""
import colorsys
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = "C:/Users/izzyn/Downloads/"
OUT = os.path.join(ROOT, "tools", "assets_out", "skins")
SHEETS = {
    "boat": ("a732129d-b1ec-4140-b52c-223823e60112.webp", 8, "left", 4.5),
    "missile": ("cd7ab50d-04c1-4a43-8b7f-2f7bee28b47e.webp", 8, "up", 5.5),
    "nuke": ("4ae1c86d-a7be-45fe-9e9d-82b1f970d5bf.webp", 8, "up", 5.5),
    "warship": ("eca17a71-0bea-4695-a4b2-439acd1189c0.webp", 8, "right", 4.5),
}
TRAIN = ("64602707-546f-4ac4-a892-180ca6d45f36.webp", 4.5)
# the train's pieces, boxes in the source image: the engine and three container cars
TRAIN_BOXES = {"loco": (50, 190, 442, 362), "car1": (444, 205, 604, 362), "car2": (606, 205, 780, 362), "car3": (782, 205, 956, 362)}

# skin id -> (kind, sheet index 1..8, recolour or None)
SKINS = {
    # boats (cargo ships)
    "boat_crimson": ("boat", 1, None),
    "boat_ocean": ("boat", 2, None),
    "boat_rust": ("boat", 3, None),
    "boat_stealth": ("boat", 4, None),
    "boat_barge": ("boat", 5, None),
    "boat_navy_grey": ("boat", 6, None),
    "boat_jungle": ("boat", 7, None),
    "boat_gold": ("boat", 8, None),
    "boat_arctic": ("boat", 2, "arctic"),
    "boat_royal": ("boat", 1, "purple"),
    "boat_neon": ("boat", 4, "neon"),
    "boat_ivory": ("boat", 6, "ivory"),
    # nukes
    "nuke_camo": ("nuke", 1, None),
    "nuke_crimson": ("nuke", 2, None),
    "nuke_hazard": ("nuke", 3, None),
    "nuke_rust": ("nuke", 4, None),
    "nuke_ice": ("nuke", 5, None),
    "nuke_toxic": ("nuke", 6, None),
    "nuke_black_ops": ("nuke", 7, None),
    "nuke_plasma": ("nuke", 8, None),
    "nuke_gold": ("nuke", 1, "gold"),
    "nuke_candy": ("nuke", 2, "pink"),
    # missiles
    "missile_field": ("missile", 1, None),
    "missile_red_streak": ("missile", 2, None),
    "missile_jungle": ("missile", 3, None),
    "missile_hazard": ("missile", 4, None),
    "missile_inferno": ("missile", 5, None),
    "missile_ice": ("missile", 6, None),
    "missile_neon": ("missile", 7, None),
    "missile_rust": ("missile", 8, None),
    "missile_shadow": ("missile", 1, "shadow"),
    "missile_plasma": ("missile", 6, "purple"),
    "missile_gold": ("missile", 4, "gold"),
    # warships
    "warship_destroyer": ("warship", 1, None),
    "warship_jungle": ("warship", 2, None),
    "warship_sub": ("warship", 3, None),
    "warship_carrier": ("warship", 4, None),
    "warship_battle": ("warship", 5, None),
    "warship_desert": ("warship", 6, None),
    "warship_stealth": ("warship", 7, None),
    "warship_dread": ("warship", 8, None),
}


def cutouts(path, n, factor):
    im = np.asarray(Image.open(DL + path).convert("RGB")).astype(np.int32)
    bg = im[4, 4]
    dist = np.sqrt(((im - bg) ** 2).sum(2))
    mask = dist > 28
    big = ndimage.binary_dilation(mask, iterations=7)
    lab, k = ndimage.label(big)
    boxes = []
    for sl in ndimage.find_objects(lab):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if h * w > 3000:
            boxes.append(sl)
    # reading order: rows by centre height, then left to right
    boxes.sort(key=lambda s: (round((s[0].start + s[0].stop) / 2 / 200), s[1].start))
    assert len(boxes) >= n, (path, len(boxes))
    return [cut(im, mask, sl, factor) for sl in boxes[:n]]


def cut(im, mask, sl, factor):
    m = ndimage.binary_fill_holes(mask[sl])
    m = ndimage.binary_opening(m, iterations=1)
    rgb = im[sl].astype(np.float32)
    a = m.astype(np.float32)
    h, w = m.shape
    nw, nh = max(1, round(w / factor)), max(1, round(h / factor))
    pre = Image.fromarray(np.clip(rgb * a[..., None], 0, 255).astype(np.uint8)).resize((nw, nh), Image.BOX)
    al = Image.fromarray((a * 255).astype(np.uint8)).resize((nw, nh), Image.BOX)
    pre = np.asarray(pre).astype(np.float32)
    al = np.asarray(al).astype(np.float32) / 255
    rgb2 = np.where(al[..., None] > 0.01, pre / np.maximum(al[..., None], 0.01), 0)
    alpha = np.where(al > 0.45, 255, 0).astype(np.uint8)
    out = np.dstack([np.clip(rgb2, 0, 255).astype(np.uint8), alpha])
    return Image.fromarray(out, "RGBA")


def recolour(img, how):
    a = np.asarray(img).astype(np.float32) / 255
    out = a.copy()
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            r, g, b, al = a[y, x]
            if al == 0:
                continue
            h, l, s = colorsys.rgb_to_hls(r, g, b)
            if l < 0.12:  # the outline stays
                continue
            if how == "gold":
                h, s, l = 0.12, max(s, 0.75), min(0.85, l * 1.15 + 0.1)
            elif how == "purple":
                h, s = 0.77, max(s, 0.6)
            elif how == "pink":
                h, s = (0.92, max(s, 0.6)) if s > 0.25 else (h, s)
            elif how == "neon":
                h, s, l = 0.45, 1.0, min(0.75, l + 0.2)
            elif how == "arctic":
                h, s, l = 0.55, min(s, 0.25), min(0.92, l * 0.6 + 0.45)
            elif how == "ivory":
                h, s, l = 0.11, min(s, 0.3), min(0.94, l * 0.5 + 0.5)
            elif how == "shadow":
                s, l = s * 0.25, l * 0.55
            r, g, b = colorsys.hls_to_rgb(h, l, s)
            out[y, x, :3] = (r, g, b)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def save(img, name, manifest):
    p = os.path.join(OUT, name + ".png")
    img.save(p)
    manifest[name] = {"file": name + ".png", "w": img.width, "h": img.height}


def build():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    sprites = {}
    for kind, (path, n, facing, factor) in SHEETS.items():
        sprites[kind] = (cutouts(path, n, factor), facing)
    for sid, (kind, idx, how) in SKINS.items():
        base, facing = sprites[kind]
        img = base[idx - 1]
        if how:
            img = recolour(img, how)
        if facing == "up":
            save(img, sid, manifest)
        else:
            right = img if facing == "right" else img.transpose(Image.FLIP_LEFT_RIGHT)
            save(right, sid + "_r", manifest)
            save(right.transpose(Image.FLIP_LEFT_RIGHT), sid + "_l", manifest)
    # the train
    im = np.asarray(Image.open(DL + TRAIN[0]).convert("RGB")).astype(np.int32)
    bg = im[4, 4]
    mask = np.sqrt(((im - bg) ** 2).sum(2)) > 28
    for name, (x0, y0, x1, y1) in TRAIN_BOXES.items():
        sl = (slice(y0, y1), slice(x0, x1))
        img = cut(im, mask, sl, TRAIN[1])
        bb = img.getbbox()
        img = img.crop(bb)
        save(img.transpose(Image.FLIP_LEFT_RIGHT), "train_" + name + "_r", manifest)
        save(img, "train_" + name + "_l", manifest)
    json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
    # a contact sheet to look at
    names = sorted(manifest)
    S = 3
    cols = 8
    cw, ch = 100, 70
    sheet = Image.new("RGBA", (cols * cw * S // 2, ((len(names) + cols - 1) // cols) * ch * S // 2), (24, 30, 50, 255))
    for i, nm in enumerate(names):
        img = Image.open(os.path.join(OUT, manifest[nm]["file"]))
        img = img.resize((img.width * S // 2 * 1, img.height * S // 2 * 1), Image.NEAREST)
        sheet.alpha_composite(img, ((i % cols) * cw * S // 2, (i // cols) * ch * S // 2))
    sheet.save(os.path.join(ROOT, "tools", "assets_out", "skins_preview.png"))
    print(len(manifest), "images")


def write_module(ids_path):
    manifest = json.load(open(os.path.join(OUT, "manifest.json")))
    ids = json.load(open(ids_path))
    def aid(name):
        return ids["http://localhost:8791/skins/" + manifest[name]["file"]]
    lines = []
    for sid, (kind, idx, how) in SKINS.items():
        if kind in ("nuke", "missile"):
            m = manifest[sid]
            lines.append('\t%s = { img = "%s", w = %d, h = %d },' % (sid, aid(sid), m["w"], m["h"]))
        else:
            m = manifest[sid + "_r"]
            lines.append('\t%s = { r = "%s", l = "%s", w = %d, h = %d },' % (sid, aid(sid + "_r"), aid(sid + "_l"), m["w"], m["h"]))
    tl = []
    for name in TRAIN_BOXES:
        m = manifest["train_" + name + "_r"]
        tl.append('\t%s = { r = "%s", l = "%s", w = %d, h = %d },' % (name, aid("train_" + name + "_r"), aid("train_" + name + "_l"), m["w"], m["h"]))
    mod = (
        "--!strict\n"
        "-- GENERATED by tools/build_unit_skins.py. Do not edit.\n"
        "-- (Take Over the World!, 2026-11-08) The unit skins' pixel art from the user's sheets, and the train:\n"
        "-- skin id -> { img (nukes, missiles: nose up) | r, l (ships: facing right / left), w, h (px) }.\n"
        "local UnitSkins = {}\n\n"
        "UnitSkins.skins = {\n" + "\n".join(lines) + "\n}\n\n"
        "--- the trains between cities (UnitLayer): the engine and the container cars, facing right / left\n"
        "UnitSkins.train = {\n" + "\n".join(tl) + "\n}\n\n"
        "return UnitSkins\n"
    )
    open(os.path.join(ROOT, "src", "shared", "Data", "UnitSkins.luau"), "w", encoding="utf-8", newline="\n").write(mod)
    print("UnitSkins.luau written")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--ids":
        write_module(sys.argv[2])
    else:
        build()
