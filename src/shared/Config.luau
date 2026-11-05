--!strict
-- Take Over the World! - every tunable lives here. Values are provisional test
-- defaults (not verified against the reference) unless noted. The match pins
-- Config.Version at round start.
local Config = {}

Config.Version = "m1.0"
Config.TickRate = 10 -- simulation ticks per second

-- Map registry. "compact" is procedural (MapGen); "earth" is rasterised from
-- Natural Earth by tools/build_earth.py into Shared.Maps.Earth.
Config.Maps = {
	earth = { Name = "World", Module = "Earth", Nations = 10, Tribes = 30, Desc = "The whole planet. 167 countries." },
	northamerica = { Name = "North America", Module = "NorthAmerica", Nations = 10, Tribes = 22, Desc = "States, provinces and the Caribbean." },
	europe = { Name = "Europe", Module = "Europe", Nations = 12, Tribes = 24, Desc = "Tight borders, fast wars." },
	africa = { Name = "Africa", Module = "Africa", Nations = 12, Tribes = 26, Desc = "A huge continent with deserts to cross." },
	korea = { Name = "Korean War", Module = "Korea", Nations = 6, Tribes = 10, Desc = "Special: North vs South at province scale.", Special = true },
	compact = { Name = "Test Island", W = 240, H = 150, Seed = 1337, LandTarget = 0.46, MinIsland = 8, Nations = 5, Tribes = 12, Hidden = true },
}
Config.MapOrder = { "earth", "northamerica", "europe", "africa", "korea" }
Config.Map = {
	Id = "earth", -- active map (pinned per round)
	PPC = 4, -- client pixels per cell
	Chunk = 32, -- cells per render chunk side
	Tile = 256, -- cells per EditableImage tile side (Tile * PPC <= 1024)
}

-- Terrain ids are stable: 0 water, 1 plains, 2 highland, 3 mountain, 4 ice, 5 desert.
Config.Terrain = {
	[0] = { name = "Water", claim = false, cost = 0 },
	[1] = { name = "Plains", claim = true, cost = 1.0 },
	[2] = { name = "Highland", claim = true, cost = 1.6 },
	[3] = { name = "Mountain", claim = true, cost = 2.6 },
	[4] = { name = "Ice", claim = false, cost = 0 },
	[5] = { name = "Desert", claim = true, cost = 1.3 },
}

Config.Match = {
	MinHumans = 1,
	MaxHumans = 12, -- human slots (8-16 for prototype)
	LobbyTime = 8,
	SpawnTime = 15,
	TimeCap = 1e9, -- no time limit: a round ends only when someone takes enough land
	ResultsTime = 20, -- results + map vote
	VictoryShare = 0.8, -- of claimable land (water excluded) - officially confirmed 80%
	EndWhenNoHumans = false, -- rounds always play out until a winner
	NoHumanGrace = 8,
	VoteOptions = 3, -- random maps offered at the end of every round
	ReconnectGrace = 20, -- seconds before AI takes over a disconnected player's nation
	MaxDrills = 3, -- tutorial air drills per player per round
}

Config.Bots = {
	-- counts come from Config.Maps[id].Nations / .Tribes
	NationThink = { 1.2, 2.4 }, -- seconds between decisions (random range)
	TribeThink = { 2.5, 5 },
}

-- solo difficulty (title screen chips): Think scales the AI's time between decisions
Config.Difficulty = {
	[0] = { Name = "Relaxed", Think = 1.7, Blurb = "Gentle AI: slower decisions, more time to grow." },
	[1] = { Name = "Standard", Think = 1.0, Blurb = "A fair fight against steady AI nations." },
	[2] = { Name = "Brutal", Think = 0.6, Blurb = "Aggressive AI that acts fast and hunts you early." },
}

Config.Spawn = {
	Radius = 3,
	BotRadius = 3,
	TribeRadius = 2,
	MinDist = 14, -- no foreign land within this many cells of a new spawn
}

Config.Troops = {
	Start = 2500,
	Base = 3000, -- cap = (Base + PerCell * land ^ CapExp) * kind mult
	PerCell = 20,
	CapExp = 0.9, -- sublinear so big nations don't snowball
	RegenBase = 12, -- troops/s
	RegenFrac = 0.022, -- share of the missing troops regained per second
	OverCapDecay = 0.05, -- share of the excess lost per second above the cap
	TribeMult = 0.55,
}

Config.Combat = {
	NeutralCost = 5, -- troops per neutral cell (x terrain cost)
	EnemyBaseCost = 8, -- troops per enemy cell (x terrain cost) ...
	DensityCost = 1.5, -- ... + defender troops-per-cell x this
	DefenderLoss = 0.55, -- defender loses troops-per-cell x this per lost cell
	NeutralFrontFrac = 0.07, -- share of the frontier taken per tick
	EnemyFrontFrac = 0.02,
	MaxCellsPerTick = 60,
	RetreatRefund = 0.8, -- manual retreat returns this share; natural end returns 100%
	MinSend = 10,
	MaxAttacks = 6,
	RatioStep = 0.05, -- Q/E step
	DefaultRatio = 0.25,
}

Config.Gold = {
	Start = 500,
	Base = 10, -- gold/s baseline
	PerCell = 0.01,
}

-- Structures. cost * growth ^ (number of that kind you already own).
-- onCapture: "transfer" keeps it for the capturer, "destroy" removes it.
-- Unfinished construction is always destroyed on capture.
Config.Structures = {
	city = { name = "City", icon = "rbxassetid://93467931382076", cost = 1000, growth = 1.5, build = 6, spacing = 4,
		capBonus = 12000, maxLevel = 5, upgradeCost = 0.8, onCapture = "transfer",
		blurb = "+%s troop capacity per level" },
	defense = { name = "Defense Post", icon = "rbxassetid://132772937710700", cost = 400, growth = 1.3, build = 4, spacing = 4,
		radius = 6, defenseMult = 1.6, onCapture = "destroy",
		blurb = "Attackers pay x%.1f troops within %d cells" },
	port = { name = "Port", icon = "rbxassetid://123083642467367", cost = 1500, growth = 1.4, build = 8, spacing = 6,
		coastal = true, onCapture = "transfer",
		blurb = "Sea trade + warships. Needs an ocean coast" },
	factory = { name = "Factory", icon = "rbxassetid://83433564904363", cost = 1500, growth = 1.4, build = 8, spacing = 6,
		onCapture = "transfer",
		blurb = "Sends trains to your cities and ports for gold" },
	silo = { name = "Missile Silo", icon = "rbxassetid://134353131057089", cost = 6000, growth = 1.5, build = 15, spacing = 6,
		onCapture = "transfer",
		blurb = "Launches nuclear missiles" },
	sam = { name = "SAM Launcher", icon = "rbxassetid://78666304883453", cost = 2500, growth = 1.3, build = 8, spacing = 4,
		radius = 14, reload = 8, onCapture = "transfer",
		blurb = "Intercepts missiles within %d cells" },
	airfield = { name = "Airfield", icon = "rbxassetid://123181184965042", cost = 3000, growth = 1.6, build = 10, spacing = 6,
		radius = 45, maxPerNation = 2, onCapture = "transfer",
		blurb = "Fighter and bomber sorties within %d cells" },
	aa = { name = "AA Battery", icon = "rbxassetid://90624716791040", cost = 900, growth = 1.25, build = 5, spacing = 4,
		radius = 7, magazine = 3, shotGap = 0.6, reload = 6, hitChance = 0.55, damage = 30, onCapture = "destroy",
		blurb = "Shoots aircraft within %d cells (not missiles)" },
}
Config.Trade = {
	TrainInterval = 12, -- seconds between trains per factory
	TrainSpeed = 8, -- cells/s
	TrainBase = 120, -- gold per delivery ...
	TrainPerCell = 3, -- ... + per cell of track
	MaxRail = 40, -- rail reach (circle radius in cells) from a factory
	ShipInterval = 18, -- seconds between trade ships per port
	ShipSpeed = 5,
	ShipBase = 250, -- gold to each side on arrival ...
	ShipPerCell = 1.2,
	InterruptNotice = 10, -- min seconds between "trade interrupted" notices
}
Config.Naval = {
	BoatSpeed = 5, -- cells/s
	BoatHp = 30, -- one warship sinks a transport in ~1.5 s; crossing its range takes ~2.6 s
	MaxBoats = 3,
	LandingSearch = 10, -- cells around an inland target to find a beach
	LaunchSearch = 120, -- max ring radius when looking for your own launch coast
	WarshipCost = 0, -- boats are free
	WarshipHp = 100,
	WarshipRange = 6,
	WarshipDps = 20,
	WarshipSpeed = 4,
	MaxWarshipsPerPort = 3,
	PatrolRadius = 10,
	PatrolEvery = 8, -- seconds idle before picking a new patrol point
}
Config.Diplomacy = {
	MaxAllies = 3,
	RequestTime = 20, -- seconds a request stays open
	DeclineCooldown = 30, -- seconds before asking the same nation again
	BreakGrace = 10, -- announced betrayal: still allied for this long
	Duration = 300, -- alliances expire after 5 minutes unless renewed
	RenewWarn = 30, -- both sides get a Renew prompt this long before expiry
	AiAcceptRatio = 0.6, -- AI accepts if the asker has >= this share of its troops
	AiBetrayChance = 0.04, -- per decision, when an ally is weak and nothing else is left
}
-- conventional missile: small blast, kills troops and destroys buildings, keeps land
Config.Missile = {
	Cost = 1500,
	Radius = 3,
	Speed = 16,
	TroopLoss = 0.25, -- each nation in the blast loses this share of the troops on the hit cells
}
Config.Nuke = {
	Cost = 5000,
	Radius = 8, -- cells
	Speed = 12, -- cells/s
	SiloCooldown = 0, -- no reload: launch as fast as you can pay
	TroopLoss = 1.5, -- troops lost = share of land lost x this
	OuterKeep = 0.4, -- share of outer-ring cells that survive
	AiMinMinutes = 6, -- AI won't launch before this
}
Config.StructureOrder = { "city", "defense", "port", "factory", "silo", "sam", "airfield", "aa" }

-- Aircraft (provisional test defaults; shared config for balance)
Config.Air = {
	SortiesPerAirfield = 1,
	Turnaround = 12, -- seconds after landing before the next sortie
	FighterCost = 0, -- planes are free (sortie limits + turnaround still apply)
	BomberCost = 0,
	StrikeEscalation = 0.5, -- +50% bomber cost per strike in the last StrikeWindow s
	StrikeWindow = 90,
	FighterSpeed = 10, -- cells/s
	BomberSpeed = 5,
	FighterHp = 50,
	BomberHp = 60,
	FighterRange = 5, -- engagement range (cells)
	FighterDps = 40, -- a lone bomber crossing a patrol dies in ~1.5 s
	CapTime = 25, -- seconds a patrol stays on station
	FrontDepth = 3, -- a front target must be this close to land the owner doesn't hold
	FrontShare = 0.12, -- front strike: defender loses this share of troops ...
	FrontCap = 2500, -- ... capped at this many
	SuppressRadius = 5,
	SuppressTime = 20, -- ground-attack window (s)
	SuppressMult = 0.6, -- attacker cost multiplier inside the window
	DisableTime = 30, -- building strike: disabled for this long
	Strikeable = { factory = true, port = true, silo = true, sam = true, aa = true, airfield = true, defense = true },
}
Config.OceanMin = 200 -- water bodies at least this many cells count as ocean (ports)

Config.Net = {
	StatsHz = 5,
	CmdPerSecond = 12,
	ResyncCooldown = 2,
}

-- Original palette (no reference colours). Humans first, then AI nations, tribes.
Config.HumanColors = {
	"E84855", "3E92CC", "F9C80E", "43AA8B", "B14AED", "FF8C42", "2EC4B6", "F15BB5",
	"9BC53D", "5C7AFF", "FF5D8F", "00BBF9", "FEE440", "8AC926", "C77DFF", "FB5607",
}
Config.BotColors = { "8E6C8A", "4F7CAC", "A0522D", "5B8E7D", "B5838D", "6D597A", "7A9E7E", "9C6644" }
Config.TribeColors = { "C98B6B", "8FA36B", "7FA6A3", "A58BB8", "C9A35B", "8C9BB5" }

Config.Flags = {} -- server-side feature flags for future content

return Config
