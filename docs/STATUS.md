# Take Over the World! — checkpoint

> **2026-11-06: the game is now RoWorld's full source** (AGPL; see NOTICE.md). `src/shared` → ReplicatedStorage.Airfront,
> `src/server` → ServerScriptService.AirfrontServer, `src/client` → StarterPlayerScripts.AirfrontClient (rw.project.json).
> Our pre-port game is in `legacy/` (not synced; its Studio scripts are parked in ServerStorage.Legacy).
> Sync: start `py -I tools/bridge.py`, then the user runs the sync loadstring from Studio's **command bar** (MCP HTTP to
> 127.0.0.1 is blocked). Big map modules go through ScriptEditorService (Source caps at 199,999 chars).
> Changed from RoWorld: branding (name, globe emblem, credits + source link; OpenFront/RoWorld notices kept), Robux product
> and subscription ids cleared (offers hidden), lobby service off. Verified: solo tutorial match, HUD, bots, lobbies; no
> script errors. Known gap: RoWorld's audio (and a few images) are private to their account, so the game is silent.
> Everything below this box describes the legacy game.

An original real-time territory-conquest game for Roblox. RoWorld is the gameplay reference; we write our own code, UI, names and art. Planes are the launch feature.

## Resume
1. Start the bridge: `py -I tools/bridge.py` from the project root (port **8767**; 8765 and 8766 belong to other projects).
2. In Studio Edit, run `execute_luau`: `loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8767/file?path=tools/sync.lua", true))()`.
3. Tests run during a playtest from the Server datamodel: `game.ServerStorage.DevHook:Invoke(name, arg)`.
   - `summary`, `hash` (ownership checksum), `rejects` (8 remote-validation checks), `win <nationId>`, `skip` (Lobby/Spawn timers only), `ff <minutes>` (async headless bot round; result in ServerStorage attribute `FF`).
   - Async tests that write a ServerStorage attribute: `structures` (attribute ST), `trade` (TR), `naval` (NV). `ports` is a sea-path diagnostic.
   - Note: requiring server modules from execute_luau gives separate module copies, so always go through DevHook.
   - Each client publishes `PlayerGui.World` attributes `OwnerHash`, `Seq` and `Winner`. Compare them with `hash` during the Ended phase.
4. Place: "Take Over The World!" (placeId 88696526459892), saved and published by the user. HttpEnabled is on for the bridge, so **turn it off before publishing**. CharacterAutoLoads is off and StreamingEnabled is off.

## Layout
- `src/shared` → ReplicatedStorage.Shared: Config (every tunable, provisional), MapGen (procedural compact map).
- `src/server` → ServerScriptService.Server:
  - Sim: grid ownership, troops, gold, attacks, deltas.
  - Bots: tribes and AI nations.
  - Match: phases, remotes, validation, replication.
  - DevTests, Main.
- `src/client` → StarterPlayerScripts.Client:
  - State: client mirror.
  - MapView: EditableImage renderer, camera, picking.
  - Hud: Clean Strategy HUD.
  - UI: the UI kit.
  - Main: net, input and glue.

## Data and network format
- Cells: `i = y*W + x` (stable ids). Adjacency is the implicit 4-neighbourhood. Terrain is u8 (0 water, 1 plains, 2 highland, 3 mountain). Owner is u16 (0 = neutral).
- Snapshot (`Cmd "hello"/"resync"`, or the `Snapshot` event at round start) carries the terrain and owner buffers, seq, nations and me.
- `Delta` (10 Hz): u32 seq, u32 count, then count × (u32 cell, u16 owner). A gap in seq makes the client resync.
- `Stats` (5 Hz): a buffer of 19 bytes per nation. `Mine` sends the player's own fronts. `Nations` fires on change. `Feed` and `Results` are events.
- Match phase lives in attributes on ReplicatedStorage.Remotes: Phase, PhaseEnds, Round, RoundStart, Claimable and Version.

## Rules (provisional; all in Config)
- One troop pool per nation, reserved once on the server when an order is sent. Cap = (3000 + 20×land^0.9) × kind multiplier. Regen = 12/s + 2.2% of the gap per second.
- Neutral cells cost 5 × terrain. Enemy cells cost 8 × terrain + 1.5 × defender density, and the defender loses 0.55 × density per cell lost.
- Opposing attacks on the same front cancel troops first. When a front runs out of troops or adjacency, survivors return 100%. A manual retreat returns 80%. An eliminated nation's commitments are lost.
- Victory: one nation holds 80% of claimable land (water excluded). Time cap is 30 minutes. Ranking: alive first, then land, peak land, troops and lower id. Dead nations rank by later elimination.
- Rounds end when every human is eliminated (8 s grace). Late joiners get a slot during Spawn; otherwise they spectate and are queued for the next round.

## Milestone 1 (playable core): status
- Done and verified in Studio (1 client):
  - Lobby → spawn pick → expansion → land combat → bots → victory → results → lobby → new round.
  - Remote validation: 8/8 rejects pass. Tick takes about 0.1–0.5 ms.
  - Client checksum equals the server's.
- Not yet run: the **2-client gate**. In Studio, choose Test → Clients and Servers → 2 players, play a round, then compare `OwnerHash` on both clients with `hash`.

## Balance data
- `ff` headless bot-only round on the compact map (1 idle human, 5 AI nations, 12 tribes): before tuning, one AI reached 80% in 7m08s; after tuning, in 10m15s. The max tick was 2.9 ms.
- Real opponents should push rounds toward the 15–25 minute target. Re-measure with players before tuning further.

## Risks
- The map renders with EditableImage. Published games need Game Settings → Security → "Allow Mesh / Image APIs", and the creator must be 13+ ID-verified. Check this before the first private publish. A fallback renderer is not built.

## Parity notes
| Mechanic | Source | Status |
|---|---|---|
| 80% world control wins | official listing | implemented |
| cities, ports, factories, alliances, nukes | official listing | M2 |
| Q/E attack ratio, X cancel | guide | implemented (Backspace also cancels) |
| right-click sends boats to water targets | guide | M2 (right-click = quick attack for now) |
| defense posts, SAM, warships, trade ships, trains | guide | M2 |
| all prices, formulas, counts | unverified | configurable assumptions |

## Milestone 2 progress
- 2A Earth map. Done. `tools/build_earth.py` turns Natural Earth 1:50m land and lakes plus 1:10m geography regions (public domain) into 512x226 Miller-projection cells, written to `src/shared/Maps/Earth.luau`. Ranges become mountains/highland, plateaus become highland, and deserts become desert. The Greenland interior is ice (unclaimable). There are 36,586 claimable cells. `Config.Map.Id` picks the map ("earth" or "compact"). The client draws one EditableImage per 256x256-cell tile. Snapshots are run-length encoded.
- 2B Structures. Done. Server/Structures covers city (+12K troop cap per level, up to Lv5), defense post (x1.6 attacker cost within 6 cells), port (ocean coast only), factory, silo and SAM.
  - Cost = base x growth^owned.
  - On capture: city, port, factory, silo and SAM transfer to the capturer; defense posts are destroyed; unfinished construction is destroyed; a pending city upgrade is lost.
  - UI: build menu (hotkeys 1-6), placement preview, confirm-on-touch, and a structure panel with Upgrade.
  - AI builds too.
  - Test `structures`: 10/10 pass.
- 2C Trade. Done. Units (path-following moving units, replicated with their paths), Trade and Path (weighted A*).
  - Factories send trains over friendly land to cities, ports and factories within 90 cells: 120 + 3 per cell of gold.
  - If a train's next cell is no longer friendly, the train is lost and the owner gets a "trade interrupted" feed message.
  - Ports send ships to other nations' ports on the same ocean: 250 + 1.2 per cell to each side.
  - HUD income shows +X/s split into base and trade. The routes overlay toggle is the button under the zoom controls.
  - Test `trade`: 4/4 pass.
- 2D Naval. Done. Boats: when a target has no land border, the order becomes "SEND BOAT".
  - The boat launches from your nearest coast on the same sea and lands on the target cell or the nearest coast of the same owner.
  - On arrival it pays the landing cost or is repelled. The beachhead then attacks the former owner with the remaining troops. If the landing cell already became yours, the troops are refunded.
  - Warships: built from a port panel (1500 gold, max 3 per port). They patrol and can be moved by selecting one and clicking water.
  - Warships engage non-allied ships within 6 cells. Priority is transport, then warship, then trade ship; a seized trade ship's cargo goes to the warship's owner.
  - Test `naval`: 3/3 pass (mid-sea interception, then landing).
- 2E Alliances. Done. Diplomacy covers request, accept, decline and break, with a maximum of 3 allies.
  - The AI accepts if the asker has at least 60% of its troops and they aren't fighting.
  - Forming an alliance ends fronts between the pair with a full refund. Attacks and nukes on allies are blocked on the server.
  - Breaking is an announced betrayal: the pair stays allied for 10 s, then becomes rivals.
  - The AI sometimes betrays a weak ally when it has nothing else to attack.
  - UI: ally button on the target panel, request cards under the leaderboard, mint ally borders, "· ally" nameplates and mint names on the leaderboard.
  - Test `diplomacy`: 8/8 pass.
- 2F Nukes. Done. Silo panel → TARGET NUKE → click a target (red blast-radius preview plus a count of hostile SAMs covering it) → LAUNCH.
  - Cost 5000. Silo reload 20 s.
  - Blast radius is 8 cells. The inner 60% becomes neutral and the outer ring keeps 40% of its cells. Troop loss = share of land lost × 1.5. Buildings and ships in the blast are destroyed.
  - Victims get a launch alert with the ETA. Every client shows a red target ring. Impact and interception flashes.
  - A SAM intercepts one hostile missile per 8 s reload within 14 cells.
  - The defense overlay button shows SAM and defense rings.
  - The AI builds SAMs and silos and launches after minute 6.
  - Test `nukes`: 4/4 pass.
- M2 headless gate (`ff 30` on Earth, 41 AI nations and tribes, all systems):
  - The round reaches 80% in 18m36s / 20m35s / 28m40s across three runs.
  - The build mix is varied, with ~100 units in play and a mid-game lead change after a nuke.
  - Profiling found trade pathfinding spikes (244 ms). It is now budgeted to 1 sea and 2 rail searches per tick, with boat launch-site search by rings and the AI neighbour scan cached for 2 s. **Max tick is now 43 ms.**
- Not yet hand-tested in the UI: nuke targeting clicks, port → warship button, selecting and moving a warship. The code paths are covered by server tests.

## Milestone 3 (planes): done
- New structures:
  - Airfield (hotkey 7): mission radius 45 cells, max 2 per nation, 1 sortie at a time, 12 s turnaround after landing.
  - AA battery (hotkey 8): radius 7, 3-shot magazine, 0.6 s between shots, 6 s reload, 55% hit chance for 30 damage. It shoots aircraft only.
  - SAMs stay missile-only. In the defense overlay SAMs are blue/orange and AA is purple.
- Server/Air.luau, mission states out → payload / hold → back → landed:
  - Fighter patrol: 400 gold, holds 25 s on station, engages within 5 cells at 40 dps, fighters first.
  - Tactical bomber: unlocks with a finished factory. 1200 gold, +50% per strike in the last 90 s.
    - Front strike (target within 3 cells of land the owner doesn't hold): defender loses 12% of troops (max 2500), and a 20 s ground-attack window gives attackers x0.6 cost within 5 cells.
    - Building strike: disables the building for 30 s. Cities can't be targeted.
  - Escort: +400 gold. The fighter uses a second airfield's sortie slot, flies in formation with the bomber and shields it.
  - Flights go in straight lines over any land. Every non-allied AA battery along the path can fire.
  - The target is rechecked on arrival; if it is no longer hostile or the building is gone, the bomber aborts.
  - If the home airfield is captured, the aircraft diverts to the nearest own airfield within 1.5x range; otherwise it is lost.
  - Simultaneous combat resolves in unit-id order.
  - Disabled buildings stop working: factories, ports, SAMs, AA, airfields, silos and defense posts.
- Feed messages:
  - The victim gets "bomber inbound, ETA" and the ground-attack window message.
  - Each AA shot result goes to both sides as a throttled toast.
  - Also reported: shot down, struck, aborted and lost.
- Client:
  - Airfield panel → PLAN MISSION.
  - The "Change" button cycles Bomber / Bomber + escort / Fighter patrol.
  - Click a target to see the preview: range ring, ETA, cost, AA on route, nearby enemy fighters, time to first contact, payload type, and why it's illegal.
  - LAUNCH (Space).
  - Aircraft face their heading. Hostile inbound routes show as red dots and your own routes as dots in your colour. Strike windows show as orange rings. AA and shoot-down flashes.
- AI builds an airfield once land > 900, builds AA when hostile airfields are near, patrols against inbound bombers (two thirds of the way in), and bombs the front it is already attacking.
- Tests:
  - `air` 6/6: strike, window, ground follow-up capture, fighter intercept, captured-home divert.
  - `air2` 2/2: AA engages; an escorted bomber delivers through a patrol.
  - Player launch through the real remote: launch OK; duplicate id, NaN cell and foreign airfield are rejected.
  - Headless Earth round: 18m44s, 38 sorties, air costs 0.3 ms per tick, max tick 44 ms.
- `airkit` dev helper gives the player a factory, an airfield and a target cell.

## Milestone 4 (release candidate): results
- New features:
  - Reconnect: a dropped player's nation is held for 20 s, then AI-controlled. A rejoin (same UserId) reclaims it while it's still alive.
  - Tutorial (client/Tutorial.luau): replayable through the "?" button. A first-visit card offers Start tutorial or Play now, which is the direct path to multiplayer.
    - 7 steps: spawn, neutral capture, commitment (Q/E or slider), attack a rival, build a City, air drill, done.
    - The air drill is real: the server's `drill` command sends a slow, harmless training drone (owned by a hidden "Training Drone" nation that never spawns) at your land. You click its red route to place a free fighter patrol. Each player gets 3 drills per round.
  - Controller: Y focuses the build menu (D-pad navigates, B leaves). The results screen focuses Requeue. Button hints switch to (X) and (B).
  - Dev tools: `noend` (keep rounds alive for load tests), `ff "12k"` (fast-forward, then keep playing live), `net` (bytes/s per player), `disconnect`, `drill`, `airkit`.
- Results (Studio emulation only; no physical devices were tested):
  - Real mouse/keyboard input:
    - Tutorial start button, then map click → Space captured neutral land, then E changed commitment; the tutorial advanced to step 4.
    - Mission planner: airfield click → PLAN MISSION → target click showed the preview (range ring, AA rings, ETA, cost, risk) → Space launched.
  - `drill`: 4/4. The drone was intercepted mid-route, and the hidden drill nation holds no land. A bug where auto-spawn gave the drill nation land was found by screenshot and fixed.
  - `disconnect`: 3/3. Human during grace, AI after grace, rejoin reclaims.
  - Lag: IncomingReplicationLag 0.3 s gave a 646 ms command round trip; commands still work. An injected out-of-sequence delta forced a client resync, and the client hash equalled the server hash (469476679 at seq 538) with the same winner.
  - Busy midgame at minute 12 (8 nations alive, 65 units, 121 structures): 6.3 KB/s per player and 0.61 ms average server tick.
  - Client in Studio: 17.2 ms average frame, 65 ms max, 2,458 PlayerGui instances; they are bounded pools.
  - Three back-to-back matches: each starts with 0 units and 0 structures, and Studio memory stays flat (2,898 → 2,876 MB).
  - No game errors.
- Open gaps:
  1. **Two-client gate** (user: Test → Clients and Servers → 2 players).
  2. Touch and controller are only code-path tested. Play them on a phone and a gamepad, or use the Studio device emulator.
  3. Nuke targeting and warship build/move have not been clicked through; they share the planner's click path, and their server logic is tested.
  4. The tutorial "seen" flag lasts one session only. Persisting it (and wins/cosmetics) needs a versioned ProfileStore profile.
  5. Publishing: turn HttpEnabled off; turn on "Allow Mesh / Image APIs" and verify the creator is 13+ ID-verified (EditableImage).
  6. Worst server tick is about 44 ms (trade rail pathfinding); acceptable at 10 Hz, but worth optimizing before 24–32 human slots.

## Update 2026-11-03: user feedback batch
- **Controls.**
  - Left-click is the order: attack land you border, or send a boat across water. Neutral attacks keep expanding until the troops run out or reach a border.
  - Right-click inspects. Hold left-click and drag to pan (position-based; a 100 px drag moves exactly 100 px).
  - Side buttons are removed. Keys: R recenter, T trade routes, G air defense, F1 tutorial, = and - zoom, Q/E ratio, 1-8 build. A MENU button sits top-left.
- **Visuals.**
  - Trade routes are flat white lines. Your aircraft routes use your colour; inbound hostile ones are red.
  - Placing or selecting a building shows its reach: factory rail reach (40-cell circle, which the server now uses too), SAM, AA, defense post and airfield.
  - The tutorial card moved under the leaderboard.
- **Maps.** `tools/build_maps.py` covers World, North America (US/Canada/Mexico states and provinces), Europe, Africa, and the Korean War special (North and South Korea only, 28 provinces at a bigger scale). All are Natural Earth, public domain. AI nations take the real name of the country or province they spawn in.
- **Main menu** (client/Menu.luau, server/ServerList.luau): map picker with client-drawn thumbnails, PLAY SOLO, HOST SERVER, SHOP, HOW TO PLAY, SPECTATE, plus a server list (map image, name, players, phase, JOIN).
  - Servers publish themselves to a MemoryStore sorted map with a 45 s TTL.
  - Solo and hosted games use TeleportService reserved servers, with the map passed in teleport data.
  - In Studio (no teleports), solo and host restart this server on the chosen map. Tested: Korean War → Play Solo.
  - Public servers rotate maps each round.
- **Shop** (shared/Cosmetics.luau, server/PlayerData.luau, server/Shop.luau, client/Shop.luau), laid out after the user's reference:
  - Featured bundle banner, crates with published odds, daily offers with a UTC reset timer, rarity-tagged cards with green coin pills, and a Locker to equip items.
  - Items: 9 territory skins (pixel patterns; Gilded and Neon also recolour the border) and 8 procedural flags shown on the nameplate.
  - Coins come from match rewards: win 300, top-3 150, played 50, plus captured cells / 20 (max 100), granted once per round. New players start with 500.
  - Robux coin packs use developer products. **Set the product ids in Cosmetics.CoinPacks.** Receipts are idempotent: saved before PurchaseGranted.
  - Crates are hidden when PolicyService reports paid random items are restricted.
  - Profile: DataStore with a session lock, autosave every 60 s, save on leave and on BindToClose. In Studio without API access it runs offline and shows "(not saved)".
  - Tested: buy, owned, not on sale, low coins, bad crate, crate roll, bundle, equip, equip-not-owned. A skin and flag show on the map.

## Update 2026-11-03 (2): feedback batch 2
- **Grid routes** (replaced the curves at the user's request). Route lines follow the real path cells as straight horizontal and vertical runs. Units face 0/90/180/270 only.
- **Vehicle models.** client/Art.luau draws 16x16 hard-edged pixel sprites with a 1px dark outline, shown with Pixelated resampling: transport, warship, trade ship, train, fighter, bomber, missile/nuke. Each has a base layer plus a tint layer in the owner's nation colour, and rotates to face its heading.
- **Vehicle skins.** Three slots (boat, plane, missile) with five palettes each: arctic, camo, stealth, neon, gold. They are sold in the shop and replicated per nation.
- **Islands.** `build_maps.py add_islands` places 4-12-cell islands in open ocean, 4-14 cells off the coast (World 45, North America 30, Europe 25, Africa 25, Korea 14). Clicking one sends a boat, which lands and expands over it. The naval test still passes.
- **Action wheel.** client/Wheel.luau offers Attack, Ally / Accept / Break, Troops, Gold and Info.
  - Opens with right-click (PC), a 0.45 s long-press (touch), or Y at the reticle (controller; D-pad/stick + A selects, B closes).
  - New server command `aid` sends 5-50% of your troops or gold (uses the commitment slider), allies only.
- **Coins.** Our own coin is a procedural gold globe (Art.coin), distinct from Robux; Robux prices show as "R$". Coins are earned every round you hold a nation, win or lose, and the amount shows on the results screen.
- **Shop.**
  - COINS tab with 3 Robux packs. **Developer product ids in Cosmetics.CoinPacks are still 0, so the buttons show "SOON".**
  - Crate opening animation: pop, escalating shake, rays, flash, then a scaling reveal card.
  - Bundles can include vehicle skins (MIDNIGHT FLEET).
  - Locker sections: territory, flag, boats, planes, missiles.
- **Factory rail preview.** While placing a factory, or with one selected, straight grid L-lines run to every city, port or factory it would serve (State.railStops, same 40-cell rule as the server).
- **UI tweaks.** The tutorial is 7 one-line steps and its card moved lower (y=262). The MENU button now sits beside the top bar.

## Update 2026-11-03 (3): feedback batch 3
- **Unit models.** These now use the user's Conquest Voxel Pack. `data/voxel/Sprites-16x16` is packed by `tools/build_sprites.py` into `client/SpriteData.luau`.
  - Standard: the hull pixels go to the tint layer, so the hull takes the owner's nation colour.
  - Arctic, Desert and Midnight keep their colours and get a 1px nation-colour outline.
  - Gold is the Standard sprite tinted gold.
  - Mapping: transport and trade ship use TroopTransport; warship uses Warship; fighter and bomber use Fighter and TacticalBomber; missile uses Nuke. Trains are procedural.
  - Sprites face up and rotate in 90° steps.
- **Grid everywhere.** Aircraft and missiles fly an L route (Path.line: horizontal then vertical). A* adds a turn penalty (+0.6) so rails and sea lanes are long straight runs.
- **Factory lines always visible.** Grid L-lines from every own factory to its stops (refreshed every 0.5 s), plus the placement preview.
- **Audio** (client/Audio.luau).
  - Menu theme: APM "Protector Of The Sky".
  - Match playlist: Imminent Closure, Under Siege, The Lost Star.
  - Ocean ambience: Pro Sound Effects.
  - SFX: click, attack sting, build hammer, explosion, intercept pop, plane, horn, nuke siren, coin, crate shake, whoosh, alert.
  - All 13 load in Studio. SFX are throttled per name. Music crossfades between menu and match.
- **Matchmaking.** HOST was removed. FIND MATCH (Menu `match`): this server if it runs that map with room, else the fullest listed server on that map, else a new public match server is generated (reserved and listed for others). PLAY SOLO is unchanged. "LIVE MATCHES" refreshes every 10 s.
- **Donut wheel** (client/Wheel.luau, after the user's reference). Ring segments are rendered into EditableImages. The hovered segment lifts and brightens. Segments: Attack red, Ally green, Troops blue, Gold gold, Info purple, Break orange. Disabled segments are grey. Picking works by angle: mouse hover/click, touch tap, gamepad stick or D-pad + A, B to close. While the wheel is open the map ignores A and stick input.
- **Shop rebuilt** (client/Shop.luau, after the user's Fortnite reference):
  - Pill tabs with a sliding marker, a section-dot rail, and italic section titles.
  - Gradient cards (wide bundle cards with an "X OFF" strikethrough price, item cards, crate cards) with NEW!/OWNED tags.
  - Right-hand preview with BUY / EQUIP / OPEN, and a controls hint bar.
  - Gamepad: X buys or equips, B closes.
- **Tweens.** Every UI.button scales on hover, select and press (UI.hover) and clicks. Panels pop or slide in: menu, shop, results, target panel, toasts, tutorial steps, feed fade, cards staggered in, wheel pop.

## Update 2026-11-04: feedback batch 4
- **Flags as territory skins.** shared/Flags.luau holds about 140 real flags plus cosmetic flags. MapView tiles a 48x32 flag pattern with terrain shading. Precedence is territory skin, then equipped flag, then the real flag for AI nations. Nameplates show the flag too.
- **Icons.** client/Icons.luau draws 16x16 pixel icons with outlines. They are used by BUILD, the wheel, structure markers and the mute buttons.
- **Wheel.** Smaller (240px: 66/116 radii) with pixel icons.
- **Routes.** The route layer lives inside the map frame with scale coordinates, so it no longer drifts while panning. Every nation's factory lines are drawn. Trade lines are faint (alpha 0.8, 1px).
- **Missiles.** Nukes fly a straight Bresenham line and their sprite rotates freely. New small Missile (1,500 gold, radius 3, kills troops and enemy structures, keeps land; shares the silo at half reload).
- **LAUNCH panel** under BUILD: Warship, Fighter and Bomber are free; Missile and Nuke cost gold. You pick a target and the server uses the nearest ready port, airfield or silo (`launch` command).
- **End of round.**
  - No time cap: the only way to win is by land share.
  - MENU is locked during Spawn and Playing.
  - Results show 3 random maps to vote on. The winner (ties and no-vote rounds are random) is the next map. Verified: a vote for Africa made the next round Africa.
- **Mute** music and SFX buttons beside MENU.
- **Shop** restyled after the Fortnite item shop: STORE / CRATES / LOCKER / COINS tabs, FEATURED + DAILY grids, rarity cards with NEW! tags, and a dithered pixel backdrop after the billboard image.
- **Sprites** from pixel_art_sprites_16x16.zip (data/sprites2 → tools/build_sprites.py, compact palette encoding under Studio's 200k source cap). Skins (arctic/desert/midnight/gold) are tints on the paint layer.
- The kill feed sits right of the BUILD/LAUNCH column (it used to overlap LAUNCH).
- Test note: injected MCP mouse input is about 57px above the screenshot coordinates (the GUI inset), so subtract it when clicking the map.

## Update 2026-11-04 (2): feedback batch 5 (RoWorld look)
- **Real pixel flags.** `tools/build_flags.py` turns flagcdn.com flag PNGs into 30x20 pixel grids.
  - Output lives in shared/FlagData (Names, PixA, PixB): 223 flags covering 295 regions, US states included. Canadian and Mexican provinces use their country's flag, and Korean provinces use KR/KP.
  - shared/FlagPix decodes them, and also renders shop flags into the same grid.
  - MapView stretches each nation's flag once over its bounding box. The box grows in x1.3 steps, so a growing nation is only redrawn a few times (one nation per frame via the `refit` queue).
- **Real terrain + ocean.** `tools/build_look.py` samples the Natural Earth rasters (NE1_50M_SR_W land cover/relief, OB_50M bathymetry, both in data/raw) into `Maps/<Module>Look.luau`. Each cell gets one character; the palette is 46 land + 18 sea colours. Unowned land and the sea use this layer, and territory is drawn as a nation colour (62%) or its flag (84%) over it.
- **Lines fixed.**
  - Factories that finished on their timer never had `done` set on the client. `State.built` now uses the timer.
  - The route layer is re-parented after the tiles, because the World gui uses Global ZIndex.
  - Rails draw at 0.5 transparency and 2px; trade lines at 0.6 and 1px.
- **Alliances last 5 min** (Config.Diplomacy.Duration).
  - In the last 30 s both sides get a Renew/Ignore card.
  - A request between existing allies renews the alliance (AI partners renew at once).
  - Feed messages: expired, renewed, renew request.
- **Planes go anywhere.** The airfield radius checks were removed from the server and client; the nearest free airfield is used.
- **No silo reload** (Nuke.SiloCooldown = 0); missiles and nukes only cost gold.
- **Missile arc.** The sprite rises, arcs over and dives, scaling with height and casting a ground shadow.
- **Shop: UNEQUIP** on equipped items (the server accepts item "").
- **RoWorld-style UI** (after the user's video, Videos/2026-11-04 00-57-02.mp4).
  - HUD:
    - Top-left icon bar: menu, music, SFX, help, leaderboard, each with a tooltip.
    - Top centre: MATCH TIME plus a WORLD CONTROL bar with the goal and leader marker.
    - Top right: rank pill, leaderboard, ATTACKS panel.
    - Bottom-left: alliance cards above the feed cards.
    - Bottom command bar: me | troops | attack % chips | gold | 8 build tools | 5 launch tools | SHOP.
    - Hover tooltip over the map: owner, tag, terrain, troops/land, "Click: attack with N".
  - Menu: full-screen pixel world map, gold logo, map cards, FIND MATCH / PLAY SOLO / SPECTATE, live matches, SHOP and HOW TO PLAY tiles, mute buttons. Audio.changed keeps every mute button in sync.
- Tests:
  - diplomacy PASS (renew expectation updated), air2 PASS, structures PASS (one placement collision), trade PASS, rejects PASS.
  - nukes: launch, no-reload and SAM PASS. The impact check timed out on a long world-map flight, so its wait is now 60 s.

## Update 2026-11-04 (3): RoWorld source study
- The user supplied Downloads/roworld-main.zip. It is AGPL-3.0, so we read its design notes and values only and copy no code.
- Applied in our own code:
  - Theme: navy glass panels (#0D1326, 84%), amber primary actions (#FFB547), cyan bars, radius 10, Rubik font (Font.fromId 12187365977, with a BuilderSans fallback).
  - Name plates: dark text (black for players, grey for nations and tribes) outlined in the owner's colour.
  - Borders: a step darker than the fill; ally borders mixed 35% toward green.
  - Leaderboard: closed at the start of each match; the rank pill toggles it, and clicking a row focuses the camera (Hud.cb.focus).
  - Nukes and missiles leave an owner-colour trail along the arc (alpha 0.59) plus a faint ground track for your own and inbound missiles.
  - Logo: fat drop shadow.

## Next
- Close the open gaps above (two-client gate, device input, publishing settings, coin pack product ids, live server-list test across real servers), then a launch review.
- Post-launch roadmap: see the build prompt §8 (Frontline Maps, Naval Aviation, Coalition Wars, New Air Missions, Ranked & Seasons).

## 2026-11-04: RoWorld UI rebuild (batch 6)
- The project now lives in `Downloads\Take Over The World!` (it moved from `Downloads\TakeOverTheWorld`).
- The user chose "Rebuild 1:1": RoWorld's look is recreated in our own code, and no AGPL code or art is copied.
- `UI.luau` kit now uses RoWorld tokens: navy glass at 84% plus an 8% boost, a 1 px white-10% inner border and a top sheen gradient. It has amber primary buttons with a 3 px lip and glass, ghost, danger, public and surrender variants. It also has pill chips, captions, dividers, `UI.wordmark` (per-glyph gradient text with a shine sweep) and `UI.blob` (EditableImage glows and vignettes).
- `Menu.luau` is the title screen. Top: emblem, shining wordmark, tag line with amber rules, a warm glow, and SHOP at the top right. Bottom glass dock: Welcome, PLAY SOLO, the PUBLIC MATCHES rule, the public card (quick play on the chosen map, live status) and How to Play.
- The solo panel has Map, Relaxed/Standard/Brutal chips and START. The map picker modal has All/Continents/Special tabs.
- Solo difficulty: `Config.Difficulty[d].Think` scales the AI nations' decision interval (`Bots.thinkMul`). It is passed through `ServerList.host` and the teleport data (`diff`).
- HUD: the top status pill uses the RoWorld layout (clock block, World control with a 7 px amber bar, You % vs crown leader). The results screen has a gradient headline (VICTORY / DEFEAT / ELIMINATED / TIME UP) and four stat tiles.
- Verified in Studio: title → solo panel → picker → quick play join → spawn → `win` → results. No script errors.

## 2026-11-04: RoWorld interface port (batch 7, AGPL)
- The user chose to make the game open source (AGPL-3.0) so RoWorld's UI could be copied verbatim. Source: https://github.com/Armxnee/take-over-the-world (public; `git push` after every change so the published source matches the game). LICENSE / NOTICE.md / README.md are in the repo root. `data/raw` is gitignored.
- `src/airfront` → ReplicatedStorage.Airfront (a ModuleScript; RoWorld's Core/Data/Net/Assets). `src/client/RW/UI` holds RoWorld's UI unchanged except for marked edits. `tools/sync.lua` now handles `init.luau` (a folder becomes a ModuleScript).
- Our adapters (src/client/RW):
  - `Feed`: builds RoWorld's GameState from our State. Troops are ×10 because RoWorld shows tenths. Our kinds map to theirs: aa→S_ARTILLERY, missile→N_ATOM, nuke→N_HYDROGEN, bomber→N_AIRSTRIKE.
  - `Session`: title/solo/public flow over the Menu remote. Intents become Cmd calls. Settings are saved server-side.
  - `World`: shim over MapView.
  - `AudioShim`: RoWorld's sounds are private to its experience, so its calls play our Audio.
  - `OurRules`: our prices, placement and radii, via UIRules.hooks.
  - `TopBar`: RoWorld Main's icon row.
  - `Boot`: starts everything. Main.client.luau has `RW_ON = true`; our Hud/Menu/Wheel stay unused (Hud is hidden).
- Server: Mine now carries `incoming` fronts; the Menu remote handles `settings_get` / `settings_set` (profile.settings, 4 KB cap) and `pause` (solo only).
- Rebranded: wordmark "TAKE OVER THE WORLD!", a globe emblem, legal notices keep "© OpenFront and Contributors" and "RoWorld changes © Snick Co.", plus the source link. Arsenal/flag shop/starter/General buttons are hidden; the crate (Locker) and SHOP buttons open our Shop.
- Verified in Studio: title, solo panel, map picker, solo start, spawn, expand, attacks panel, build (with cost growth), tooltips, coach tips, radial menu, alliance, leaderboard, game menu, victory screen, next round. No errors.
- Open:
  - Fighter patrol has no slot in RoWorld's bar (the bomber has one).
  - There is no end-of-round map vote UI; the server picks among its 3 options.
  - RoWorld's Locker/FlagShop are not wired to our shop backend.
  - RoWorld's first-match tutorial is untested with our rules.
  - The 2-client gate.

## 2026-11-06: batch 8 (open items from batch 7)
- Fighter patrol slot: RoWorld's bar has a new Arsenal kind `fighter` after the bomber (UIRules, OurRules, Session `LAUNCH_OF`). Its glyph is our fighter sprite as a white mask (`tools/assets_out/fighter_icon.png`, rbxassetid://116041021374110, in ArsenalArt.ui). It fires in one click like a strike and can target your own or allied land. The radial menu offers it over your own land as well.
- End-of-round map vote: the GameOver screen has a "VOTE FOR THE NEXT MAP" row. It shows the server's `results.vote` maps with live counts from the Vote remote (`Feed.state.vote_counts`), and your pick is shown in gold. A vote is sent as the intent `vote` → Cmd `vote`.
- Fix: the RoWorld aim tooltip called `tonumber(world_call("aim_sams"))` while our World shim returned nothing, which errored on every strike or nuke hover. `World.aim_sams` now counts the hostile finished SAMs that cover the missile or nuke aim.
- Verified in Studio: the fighter slot is lit with an airfield, it launches over your own land, the fighter flies, the vote row appears and counts, and the voted map (Africa) loaded for the next round. No script errors.
- **Sync note:** Studio now blocks MCP `execute_luau` HTTP to 127.0.0.1 ("not in the Assistant HTTP allowlist"), so `tools/sync.lua` cannot run that way. This batch was applied with MCP `multi_edit` (the same diffs as on disk). For a full re-sync, run the sync loadstring from Studio's command bar.
- Still open: RoWorld's Locker/FlagShop are not wired to our shop backend, the first-match tutorial is untested with our rules, and the 2-client gate.

## 2026-11-06: Stages 4 and 5 removed
- At the user's request the armies (Stage 4) and logistics (Stage 5) were reverted (commits fd8920a, f76e94a stay in history).
  Kept: the RoWorld port + country selection and provinces (Stage 3), with its two later bug fixes (troop growth above the cap, picker income).

## 2026-11-06: native audio, fitted flags, item shop gear, tweens
- Audio: only Roblox-licensed sounds (Roblox UI kit, APM Music, Pro Sound Effects); tools/native_audio.py
  writes Assets/{Audio,AudioExtra,AudioUI,Soundtrack}.luau (lengths measured in Studio; long sounds cut
  with playback regions).
- Territory flags: MapSurface._flag_skin cover-fits one FlagPix flag to each country's home land
  (CountryGrid, 5th-95th percentile bounds); tiled only without a grid.
- Quests / Item Shop buttons: new icons (tools/assets_out/icons, rbxassetid 110859228590510 / 116782632104302).
- Item shop (UI/ItemShopPanel): 2 FEATURED + 6 DAILY cards (Data/ItemShop.featured by UTC day), crate +
  My Crates cards, NEW! = not on sale yesterday; an owned card equips / takes off.
- Data/Gear: 9 Countryball hats (drawn by Countryball.ball_content) and boat / nuke / missile colour skins
  (UnitLayer tint_of). Slots in Cosmetics.SLOTS, end to end: Purchases clean/equip, MatchServer
  cosmetics_map, GameState.set_cosmetics, Session._apply_own_cosmetics. 30% of bot players wear a hat / boat.
- UI/Anim: dim fade + panel pop + staggered pops; button hover / press scale (shop, quests).
- Studio MCP mouse input takes GUI coordinates (screenshot y minus the 58 px top bar).
- Not yet seen in a match: hats on nameplates and tinted units (test account can't afford one).

## 2026-11-07: shop rebuilt full screen, gear only, live flag fit
- Item shop (UI/ItemShopPanel): full screen over a pixel showroom (tools/build_shop_bg.py, original art,
  rbxassetid 84971757872319; our coin on the floor platform): 3 FEATURED + 6 DAILY cards, banners with
  timers, crates bought / opened from the top bar. UI/GearArt draws every gear picture (shop, Locker,
  crate reveal).
- No territory skins: MapSurface always paints the flag; crates roll gear (Cosmetics `order` = gear +
  name flags); Locker tabs Hats / Boats / Nukes / Missiles / Flags; Gear rarities = the crate's four.
- Buying wears the item when its slot is empty. Session's INVENTORY copy keeps every slot (it kept only
  skin / flag: hats never reached the nameplate). Nameplate Countryball drawn 1.8x the name height.
- Flags follow the owner's land: MapSurface._refit_step scans owners' tiles incrementally and refits
  (3rd-97th percentile bounds) when the fit moves more than 12%.
- Test coins: workspace AF_DIAG = true (Studio only), then LocalPlayer af_cmd = "stars 30000". Turn it off after.

## 2026-11-07 (2): bundles, coin packs, empires, AI Countryballs, flag colours
- Robux products (this universe, made by the user in Creator Dashboard): bundles royal 3729153353,
  admiral 3729153448, winter 3729153535, frontline 3729153618; coins s 3729153677, m 3729153745,
  l 3729153826, xl 3729153911. Data/Products marks them `own` (every RoWorld product is zeroed).
  Data/Bundles lists them; server/Purchases.grant handles "coins:<n>" and "bundle:<id>" (owned items
  come back as coins).
- Item shop: sections scroll (featured + daily, then BUNDLES); top bar BUY COINS / MY ITEMS overlays
  (no crates).
- Empires (Data/Empires, Sim.form_empire, intent "empire", UI/EmpireButton): a player's country with 5%
  of the map's land founds its empire (19 historical, else "Empire of <name>"); flags from Wikimedia
  Commons pixelated by tools/build_empire_flags.py into Data/FlagData/Empires; Countries.flags_by_name maps
  empire names to them; empire Countryballs get a moustache and a beard.
- Every country's Countryball by its name (NameLayer: any owner with a flag); nation colours = their
  flag's main colour (FlagPix.main_color, kept exactly in Sim._create_nations).
- US flag hand-drawn (FlagPix.OVERRIDES).

## 2026-11-08: empire card, AI empires, evil empire balls, US flag
- UI/EmpireButton: a HUD glass card (UITheme GLASS / LINE / AMBER tokens, HUD scale) under the top bar:
  the empire's Countryball, its name, the % of the land needed and an amber bar like the world-control bar.
  Ready: an amber button with dark INK text and no text outline ("FOUND THE <EMPIRE>!"), readable.
- AI nations found their empires too: Sim.can_form_empire takes KIND_NATION; SimAI._think_nation founds it
  as soon as it can (everyone gets the "<country> founded the <empire>!" message). CountryTests 32/32.
- Empire Countryballs look evil (Countryball EVIL_EYE / EVIL_MOUTH: angry brows, red eyes, curled
  moustache, fanged grin) instead of the beard.
- US flag (FlagPix.OVERRIDES.us): 25 staggered one-pixel stars; a star on every pixel read as a checkerboard.

## 2026-11-08 (2): gear from the user's sheets, evil empires, item shop rework, tween polish
- tools/build_gear.py cuts the user's reference sheets (Downloads: hats, beards/moustaches/horns, glasses,
  the evil empire ball) into pixel sprites -> src/shared/Data/GearSprites.luau (24 items + 12 recoloured
  variants), pixelates images.jpg into the shop backdrop (rbxassetid 109594632689836) and cleans the
  basket icon (rbxassetid 85914348579343: item shop title + top-bar button). Uploads: serve
  tools/assets_out with `py -m http.server`, then MCP upload_image with localhost URLs.
- Old hats removed. New slots `beard` and `glasses` beside `hat`, end to end (Gear.KINDS / BALL_KINDS,
  Cosmetics.SLOTS, Session, GameState.set_cosmetics, MatchServer cosmetics map + bots, NameLayer,
  CountryPicker, Locker tabs, crate / shop kind labels). Bundles point at new hat ids.
- Countryball canvas is now 40 x 40 (the 32 px ball at 4, 7) so hats sit above the head. Empires: the
  angry eyes and spiked helmet sampled 1:1 from the user's evil ball + the handlebar moustache (own
  gear wins in its slot).
- Anim: Quint glides, softer Back pops, Anim.rise / sink / home, modals grow + rise in and settle out.
  RoWorld UI helpers default to Quint. Item shop: city zooms in and drifts, title drops in, cards rise
  in a diagonal wave with their art fading in; closing sinks + fades and resets.
- Studio sync note: GameState, CountryPicker and a few others hold CRLF in Studio; multi-line anchors
  fail there (use single-line edits). Studio's Session has the cosmetics line on one line (same code).
- (later, same day) Gear fitted to the ball after the user's references: hats fill the ball's top down to a
  dark brim line at y=11 (just over the eyes), full beards / elder / ginger fill the lower half (rising at
  the cheeks) with an open mouth, the goatee the chin, the chinstrap a band on the lower rim; all inside the
  outline (build_gear.py `fit`). Moustaches, horns and glasses stay free sprites. Countryball is back to a
  32 x 32 canvas (no headroom); beards draw under the eyes.
- (later) Glasses are drawn around the ball's own eyes by build_gear.py `glasses()` (frames over x 7..15 /
  16..24 from row 11, arms on row 12 out to the ball's edge, clear lenses where the eyes show; VR, NVG,
  monocle and eye patch drawn to fit; colours after the user's eyewear sheet). Moustaches are wider and
  clipped to the ball. The item shop never offers an item that is in a Robux bundle (Data/ItemShop); 15
  new boat / nuke / missile skins (Data/Gear) keep its unit skins varied.
- (later) An empire's pieces give way to the player's gear, slot by slot: glasses replace the angry eyes (the ball's usual eyes go under them), a hat the spiked helmet, a beard the handlebar moustache.

## 2026-11-08 (3): empire rule, empire circle, picker info, front-line soldiers
- Empires.need(land, home) = max(LAND_SHARE 5% of the map, the country's own land (def.tiles) +
  CONQUER_SHARE 2% of the map): big countries (Antarctica 30%, Russia, China...) no longer found an
  empire at the start; AI and players alike must conquer. Sim.can_form_empire uses it; CountryTests 32/32.
- UI/EmpireButton is now a progress ring (EditableImage, amber arc; gold + pulsing glow when full)
  with the empire's Countryball inside, placed right of the top status pill (UIRoot passes
  top.panel.gui). Hover / tap shows "<EMPIRE> · n% done · m% to go"; click founds it when full.
- CountryPicker card: an EMPIRE row (evil empire ball, name, "Hold x% of the map · conquer y% more").
- FrontLayer: at each front label two of the player's soldiers face two of the enemy's (Countryball
  with combat helmet, an empire's with its spiked helmet; rifle cut from the user's soldier image,
  GearSprites.soldier.rifle, mirrored by facing), firing: muzzle flash, tracer, spark, recoil.
  Facing comes from front_dir (owners in an 11x11 window). Countryball.ball_content(code, name, gear, pose).
