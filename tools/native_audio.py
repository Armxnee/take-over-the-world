"""Roblox-licensed audio for every sound slot (Take Over the World!, 2026-11-06).

Only sounds Roblox licenses for every experience: the Roblox UI kit (creator Roblox), APM Music
(creator APMOfficial) and Pro Sound Effects (creator ProSoundEffects). Lengths were measured in Studio
(Sound.TimeLength). A long sound is cut with a playback region: (id, length) or (id, start, stop).
Writes src/shared/Assets/{Audio,AudioExtra,AudioUI,Soundtrack}.luau.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "shared", "Assets")

# the sounds: name -> (asset id, measured length)
S = {
    "click": (15675059323, 0.371),          # Roblox: Bright_Click
    "tick": (15675032796, 0.133),           # Roblox: Small_Click
    "whoosh": (15675024286, 0.852),         # Roblox: Whoosh_01
    "whoosh2": (15675028888, 0.486),        # Roblox: Whoosh_02
    "error": (15675075163, 0.611),          # Roblox: Delete
    "pop": (15675055424, 2.704),            # Roblox: Cute_Pop
    "stinger": (15675043410, 1.472),        # Roblox: Tonal_Stinger
    "indicator": (15675085146, 3.372),      # Roblox: Indicator
    "sweep": (15675046931, 0.611),          # Roblox: Sweep
    "paper": (15675037413, 0.617),          # Roblox: Paper_Swipe
    "goodbye": (15675081158, 0.281),        # Roblox: Cute_Goodbye
    "fanfare": (1836473422, 9.979),         # APM: Victory Fanfare Sting
    "bridges": (1838583668, 12.135),        # APM: Four Short Fanfare Bridges 3
    "spirit": (1836860398, 5.701),          # APM: Winning Spirit
    "election": (9042409054, 6.034),        # APM: Day Of The Election Sting 2
    "price_of_war": (99170625394811, 11.446),  # APM: The Price Of War Sting 2
    "encircling": (9042970687, 12.565),     # APM: Encircling Sting 1
    "timp_g": (1846435467, 4.702),          # APM: Timpani Effect G
    "timp_c": (1846435334, 6.426),          # APM: Timpani Effect C
    "timp_signal": (1846284814, 6.426),     # APM: Timpani Signal 1
    "march_drum": (1840271646, 6.060),      # APM: Marching Drum (C)
    "siren": (9118781307, 5.982),           # PSE: Sci-Fi Siren
    "splash": (9116324604, 5.368),          # PSE: Logs And Boards Splash 4
    "splash2": (9116325883, 5.413),         # PSE: Logs And Boards Splash 8
    "explosion": (9114224354, 7.387),       # PSE: Earthquake Explosion 1
    "coins": (9113849492, 1.245),           # PSE: Coins Or Keys Jingle 6
    "coin_throw": (9113849651, 1.384),      # PSE: Coin Throws 3
    "hammer": (9114755820, 4.027),          # PSE: Hammer Nail Into Wood 2
}


def entry(name, stop=None, start=0.0):
    sid, length = S[name]
    rid = "rbxassetid://%d" % sid
    if stop is None or stop >= length:
        return '{ id = "%s", length = %s }' % (rid, round(length, 3))
    return '{ sprite = "%s", start = %s, stop = %s, length = %s }' % (rid, start, stop, round(stop - start, 3))


AUDIO = {
    "alliance": entry("stinger"),
    "ally_request": entry("indicator", 1.2),
    "attack_launch": entry("whoosh2"),
    "betrayal": entry("encircling", 3.4),
    "boat_launch": entry("splash", 1.6),
    "build": entry("hammer", 1.2),
    "conquer": entry("bridges", 3.0),
    "countdown_tick": entry("tick"),
    "defeat": entry("price_of_war"),
    "expand": entry("pop", 0.5),
    "game_start": entry("election"),
    "nuke_alarm": entry("siren", 2.8),
    "nuke_explosion": entry("explosion"),
    "nuke_launch": entry("timp_signal", 2.5),
    "order_ack": entry("tick"),
    "sam_intercept": entry("explosion", 0.9),
    "sam_launch": entry("whoosh2"),
    "shell_fire": entry("timp_c", 0.5),
    "shell_hit": entry("timp_g", 0.45),
    "shell_splash": entry("splash", 0.6),
    "ship_sink": entry("splash2", 2.2),
    "spawn_confirm": entry("stinger"),
    "ui_click": entry("click"),
    "ui_error": entry("error"),
    "ui_hover": entry("tick"),
    "ui_open": entry("whoosh2"),
    "under_attack": entry("siren", 1.3),
    "victory": entry("fanfare"),
    "warship": entry("march_drum", 2.5),
}

EXTRA = {
    "card_flip": entry("paper"),
    "card_whoosh": entry("whoosh2"),
    "countdown_gamestart": entry("spirit", 3.25),
    "countdown_tick": entry("tick"),
    "countdown_tick_1": entry("click"),
    "countdown_tick_2": entry("click"),
    "countdown_tick_3": entry("click"),
    "countdown_tick_4": entry("click"),
    "countdown_tick_5": entry("click"),
    "crate_drop": entry("whoosh"),
    "crate_land": entry("timp_g", 0.58),
    "crate_open": entry("coin_throw"),
    "crate_preview_common": entry("sweep"),
    "crate_preview_epic": entry("sweep"),
    "crate_preview_legendary": entry("sweep"),
    "crate_preview_rare": entry("sweep"),
    "crate_rattle": entry("coins", 0.7),
    "crate_shimmer": entry("indicator"),
    "game_start": entry("election"),
    "queue_start": entry("stinger"),
    "reveal_common": entry("stinger"),
    "reveal_epic": entry("bridges", 2.67),
    "reveal_legendary": entry("fanfare", 2.9),
    "reveal_rare": entry("spirit", 2.67),
    "spawn_confirm": entry("click"),
    "spectate_switch": entry("sweep"),
}

UI = {
    "buy_spend": entry("coin_throw"),
    "eliminate": entry("timp_g", 0.61),
    "expand_pop": entry("pop", 0.3),
    "star_get": entry("coins"),
    "star_tick": entry("tick"),
    "ui_back": entry("goodbye"),
    "ui_click": entry("click"),
    "ui_confirm": entry("stinger"),
    "ui_error": entry("error"),
    "ui_hover": entry("tick"),
    "ui_locked": entry("error"),
    "ui_open": entry("whoosh2"),
    "ui_tab": entry("sweep"),
    "unlock": entry("fanfare", 3.6),
}

# the soundtrack (APM Music, licensed for Roblox): key -> (id, length, title)
TRACKS = {
    "determined_epic_theme": (1836104037, 67.492, "Determined Epic Theme (Alt 2)"),
    "epic_and_ceremonial": (1836075862, 131.763, "Epic And Ceremonial (Alt 3)"),
    "glory_awaits": (9043653262, 119.536, "Glory Awaits (Alternative Mix)"),
    "ancient_grounds": (9045929119, 128.418, "Ancient Grounds (Underscore)"),
    "age_of_progress": (1840810639, 65.672, "Age Of Progress"),
    "epic_quest": (1845349070, 91.516, "Epic Quest"),
    "on_the_warpath": (1837240654, 114.805, "On the Warpath"),
    "deadly_assault": (1846877907, 62.245, "Deadly Assault"),
    "fight_for_a_tomorrow": (1848108091, 61.608, "Fight For A Tomorrow"),
    "stalking_the_prey": (1835248722, 61.967, "Stalking the Prey"),
    "imminent_closure": (9046506025, 110.498, "Imminent Closure (Underscore C)"),
    "counter_assault": (1836763619, 116.68, "Counter Assault"),
}
MOODS = {
    "title": ["determined_epic_theme", "epic_and_ceremonial", "glory_awaits"],
    "wait": ["ancient_grounds", "age_of_progress"],
    "calm": ["ancient_grounds", "age_of_progress", "epic_quest"],
    "war": ["on_the_warpath", "deadly_assault", "fight_for_a_tomorrow", "stalking_the_prey", "imminent_closure", "counter_assault"],
    "victory": ["glory_awaits"],
    "defeat": ["ancient_grounds"],
}

HEAD = "-- GENERATED by tools/native_audio.py — do not edit by hand.\n"
NOTE = ("-- Roblox-licensed audio only (2026-11-06): the Roblox UI kit, APM Music and Pro Sound Effects.\n"
        "-- sfx entries are {id, length}, or {sprite, start, stop, length} for a cut region.\n")


def sfx_block(d):
    return "".join("\t\t%s = %s,\n" % (k, d[k]) for k in sorted(d))


def write(name, body):
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(body)
    print("wrote", name)


def main():
    mt = TRACKS["determined_epic_theme"]
    wt = TRACKS["on_the_warpath"]
    write("Audio.luau", HEAD + NOTE + "return {\n\tmusic = {\n"
          + '\t\tmenu = { id = "rbxassetid://%d", length = %s },\n' % (mt[0], mt[1])
          + '\t\twar = { id = "rbxassetid://%d", length = %s },\n' % (wt[0], wt[1])
          + "\t},\n\tsfx = {\n" + sfx_block(AUDIO) + "\t},\n}\n")
    write("AudioExtra.luau", HEAD + NOTE + "-- AudioDirector merges these over Assets/Audio's sfx.\n"
          + "return {\n\tsfx = {\n" + sfx_block(EXTRA) + "\t},\n}\n")
    write("AudioUI.luau", HEAD + NOTE + "-- The interface kit; AudioDirector merges these over Assets/Audio and Assets/AudioExtra.\n"
          + "return {\n\tsfx = {\n" + sfx_block(UI) + "\t},\n}\n")
    tr = "".join('\t\t%s = { id = "rbxassetid://%d", length = %s, title = "%s", pack = "APM Music" },\n'
                 % (k, v[0], v[1], v[2]) for k, v in sorted(TRACKS.items()))
    mo = "".join("\t\t%s = { %s },\n" % (k, ", ".join('"%s"' % x for x in v)) for k, v in MOODS.items())
    write("Soundtrack.luau", HEAD
          + "-- Music courtesy of APM Music, licensed by Roblox for use in experiences.\n"
          + "-- tracks: key -> {id, length (s), title, pack}; moods: playlists by mood, the first title track\n"
          + "-- is the opener. Played whole (intro to ending) and crossfaded by AudioDirector.\n"
          + 'return {\n\tcredit = "Music courtesy of APM Music",\n\tlicense = "Roblox licensed audio",\n'
          + "\ttracks = {\n" + tr + "\t},\n\tmoods = {\n" + mo + "\t},\n}\n")


if __name__ == "__main__":
    main()
