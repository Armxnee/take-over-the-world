# Notices

Take Over the World! is free software: you can redistribute it and/or modify it under the terms of the
GNU Affero General Public License version 3 (see LICENSE). Because it is played over a network, everyone who
plays it can get its full source code from this repository (AGPL-3.0 section 13); the title screen links here.

## Third-party code and art
- **RoWorld** (Roblox port of Airfront / OpenFront): the user-interface framework, screens, UI art and icons
  in `src/client/RW/UI/`, `src/client/RW/Audio/`, `src/client/RW/Map/`, `src/client/RW/TopBar.luau` and
  `src/airfront/` (ReplicatedStorage.Airfront) are copied from RoWorld and modified to fit this game.
  The adapters in `src/client/RW/` (Boot, Session, Feed, World, AudioShim, OurRules) are this game's own.
  © OpenFront and Contributors, licensed under GNU AGPL v3.
- **Music**: "Orchestral Ambients" by Rodrigo Flores, CC BY 4.0.
- **Map data**: Natural Earth (public domain), used by `tools/build_maps.py` and `tools/build_look.py`.
- **Flags**: flagcdn.com / Wikimedia Commons (public domain or CC0 files).

## Changes
These files were changed from RoWorld (2026-11-04 onward): their game Session and globe view are replaced with
adapters for this game's 2D map simulation; names, branding and shop items are this game's own.
