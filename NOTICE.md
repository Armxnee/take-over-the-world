# Notices

World Conquest (formerly Take Over the World!) is free software: you can redistribute it and/or modify it under the terms of the
GNU Affero General Public License version 3, with the additional terms at the end of LICENSE. Because it is
played over a network, everyone who plays it can get its full source code from this repository (AGPL-3.0
section 13); the title screen links here.

## Origin
- **RoWorld** (© 2026 Snick Co.), itself a modified version of **OpenFront** (© OpenFront and Contributors),
  both under GNU AGPL v3. Since 2026-11-06 this game *is* RoWorld's full source (`src/shared`, `src/server`,
  `src/client`, laid out as in RoWorld's `default.project.json`, kept here as `rw.project.json`), modified as
  listed below. World Conquest is not affiliated with or endorsed by OpenFront or RoWorld, and does not
  use either name as its title.
- **Music**: "Orchestral Ambients" by Rodrigo Flores, CC BY 4.0.
- **Map data**: Natural Earth and NOAA ETOPO1 (public domain). **Flags**: Wikimedia Commons / flagcdn.com
  (public domain or CC0 files).
- `legacy/` holds this game's own code from before 2026-11-06 (its first simulation, 2D map and UI adapters).
  It is not part of the running game.

## Changes from RoWorld (2026-11-06 onward)
Every changed spot is marked in the code with a comment starting `(Take Over the World!:` (the game's former name). Git history has
the exact diff and date of each change.
- Name and emblem: the title wordmark, the rotate card, the credits footer, Help & Credits and the source link
  name this game; the "© OpenFront and Contributors" and RoWorld notices stay visible (LICENSE section 7(b)).
- RoWorld's Robux developer products, subscription and lobby service belong to RoWorld's experience: their ids
  are cleared (offers hidden) and the lobby service is off (MemoryStore lobbies only).
