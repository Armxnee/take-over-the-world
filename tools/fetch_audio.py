"""Music and sound effects from Freesound, CC0 only (Take Over the World!, 2026-11-06).

For each slot: a Freesound search limited to Creative Commons 0 (public domain) and a duration range,
most downloaded first; the top result's HQ preview (mp3) is saved to tools/assets_out/audio/<slot>.mp3
and its id, title, author and license go to tools/assets_out/audio/credits.json.
(Pixabay was asked first, as the user wanted, but it refuses scripted downloads.)
"""
import json, os, re, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tools", "assets_out", "audio")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}

# slot: (query, min seconds, max seconds)
SLOTS = {
    "click": ("ui click", 0, 0.6),
    "whoosh": ("ui whoosh", 0, 1.5),
    "error": ("error beep", 0, 1.5),
    "tick": ("clock tick", 0, 0.6),
    "build": ("hammer construction", 0.3, 2.5),
    "pop": ("pop", 0, 0.7),
    "drum": ("drum roll", 1, 4),
    "cannon": ("cannon shot", 0.2, 2.5),
    "explosion": ("explosion", 1.5, 6),
    "siren": ("air raid siren", 1, 6),
    "launch": ("rocket launch", 1, 5),
    "splash": ("water splash", 0.3, 2.5),
    "chime": ("positive chime", 0.3, 2.5),
    "fanfare": ("victory fanfare", 1, 8),
    "defeat": ("fail trumpet", 1, 6),
    "coin": ("coin", 0, 1.5),
    "crate": ("chest open", 0.3, 3),
    "music_menu": ("orchestral music loop", 40, 240),
    "music_calm": ("calm piano music", 40, 240),
    "music_war": ("epic battle music", 40, 240),
}


def fetch(url, binary=False):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def search(query, lo, hi):
    f = 'license:"Creative Commons 0" duration:[%s TO %s]' % (lo, hi)
    url = "https://freesound.org/search/?" + urllib.parse.urlencode({"q": query, "f": f, "s": "Downloads (most first)"})
    html = fetch(url)
    out = []
    for m in re.finditer(r'previews/(\d+)/(\d+)_(\d+)-lq\.mp3', html):
        out.append((m.group(2), "https://cdn.freesound.org/previews/%s/%s_%s-hq.mp3" % (m.group(1), m.group(2), m.group(3))))
    seen, uniq = set(), []
    for sid, u in out:
        if sid not in seen:
            seen.add(sid)
            uniq.append((sid, u))
    return uniq


def info(sid):
    html = fetch("https://freesound.org/s/%s/" % sid)
    title = re.search(r'<meta property="og:title" content="([^"]*)"', html)
    user = re.search(r'freesound.org/people/([^/"]+)/sounds/%s' % sid, html)
    lic = "Creative Commons 0" if "publicdomain/zero" in html or "Creative Commons 0" in html else "?"
    return (title.group(1) if title else sid), (urllib.parse.unquote(user.group(1)) if user else "?"), lic


def main():
    os.makedirs(OUT, exist_ok=True)
    credits = {}
    for slot, (q, lo, hi) in SLOTS.items():
        try:
            res = search(q, lo, hi)
            if not res:
                print(slot, "no result")
                continue
            used = {c["id"] for c in credits.values()}
            pick = [r for r in res if int(r[0]) not in used]
            if not pick:
                print(slot, "only duplicates")
                continue
            sid, url = pick[0]
            title, user, lic = info(sid)
            if lic != "Creative Commons 0":
                print(slot, "skipped (license?)", sid)
                continue
            data = fetch(url, binary=True)
            with open(os.path.join(OUT, slot + ".mp3"), "wb") as f:
                f.write(data)
            credits[slot] = {"id": int(sid), "title": title, "author": user, "license": lic,
                             "url": "https://freesound.org/s/%s/" % sid, "bytes": len(data)}
            print(slot, sid, title, "by", user, len(data))
            time.sleep(1)
        except Exception as e:
            print(slot, "error", e)
    with open(os.path.join(OUT, "credits.json"), "w", encoding="utf-8") as f:
        json.dump(credits, f, indent=1)


if __name__ == "__main__":
    main()
