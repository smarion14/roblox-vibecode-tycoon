--!strict
-- All tunable numbers live here. Code reads from this table and never hard-codes values.

export type ClientDef = {
	Id: string,
	Name: string,
	Project: string,
	TierMultiplier: number,
	UnlockAtDeploys: number, -- counted on deploys shipped within the client's act
	Act: number,
}

export type GearDef = {
	Name: string,
	Price: number,
	TimeBonus: number?,
	PreviewNext: boolean?,
	ForgiveEdits: number?,
}

export type HireDef = {
	Name: string,
	Price: number,
}

local GameConfig = {}

GameConfig.COMPONENTS = { "FrontendUnits", "BackendEndpoints", "DatabaseTables", "PromptTokens" }

GameConfig.STATION_NAMES = {
	FrontendUnits = "Frontend Terminal",
	BackendEndpoints = "Server Rack",
	DatabaseTables = "Database Console",
	PromptTokens = "AI Model Rig",
} :: { [string]: string }

GameConfig.RECIPES = {
	LandingPage = { FrontendUnits = 2, BackendEndpoints = 1, DatabaseTables = 1, PromptTokens = 1 },
	MobileApp = { FrontendUnits = 2, BackendEndpoints = 2, DatabaseTables = 1, PromptTokens = 1 },
	Game = { FrontendUnits = 1, BackendEndpoints = 1, DatabaseTables = 1, PromptTokens = 3 },
} :: { [string]: { [string]: number } }

GameConfig.CLIENTS = {
	{ Id = "PawsAndSuds", Name = "Paws & Suds Grooming", Project = "LandingPage", TierMultiplier = 20, UnlockAtDeploys = 0, Act = 1 },
	{ Id = "RollingTaco", Name = "Rolling Taco Truck", Project = "LandingPage", TierMultiplier = 30, UnlockAtDeploys = 2, Act = 1 },
	{ Id = "CornerBakery", Name = "Corner Bakery", Project = "LandingPage", TierMultiplier = 40, UnlockAtDeploys = 4, Act = 1 },
	-- Act 2: startups and agencies, unlocked by deploys shipped since moving into the office.
	{ Id = "PocketFit", Name = "PocketFit Fitness App", Project = "MobileApp", TierMultiplier = 55, UnlockAtDeploys = 0, Act = 2 },
	{ Id = "PixelForge", Name = "PixelForge Indie Studio", Project = "Game", TierMultiplier = 70, UnlockAtDeploys = 2, Act = 2 },
	{ Id = "BrewCrew", Name = "BrewCrew Coffee Rewards", Project = "MobileApp", TierMultiplier = 85, UnlockAtDeploys = 4, Act = 2 },
} :: { ClientDef }

GameConfig.GEAR = {
	MechanicalKeyboard = { Name = "Mechanical Keyboard", Price = 300, TimeBonus = 2 },
	SecondMonitor = { Name = "Second Monitor", Price = 500, PreviewNext = true },
	ModelV2 = { Name = "Model v2", Price = 800, ForgiveEdits = 1 },
} :: { [string]: GearDef }

GameConfig.HIRES = {
	FrontendUnits = { Name = "Frontend Intern", Price = 250 },
	BackendEndpoints = { Name = "Backend Intern", Price = 250 },
	DatabaseTables = { Name = "Database Intern", Price = 250 },
	PromptTokens = { Name = "Prompt Intern", Price = 250 },
} :: { [string]: HireDef }

GameConfig.BURST_PROMPT_COUNT = 3

-- Which minigame each station plays. Typing stations use BURST_RULES; the rest use MINIGAMES below.
GameConfig.STATION_MINIGAMES = {
	FrontendUnits = "Typing",
	BackendEndpoints = "PatchPanel",
	DatabaseTables = "RaidRebuild",
	PromptTokens = "TrainingRun",
} :: { [string]: string }

GameConfig.MINIGAMES = {
	-- Server Rack: rotate cable tiles to route the router to the server.
	PatchPanel = { Cols = 5, Rows = 4, TimeLimit = 25 },
	-- Database Console: repeat the NAS drive-bay flash sequence; each round adds a step.
	RaidRebuild = {
		Bays = 4,
		Rounds = 4,
		StartLength = 3,
		StepSeconds = 0.55,
		InputSecondsPerStep = 1.4,
		InputGrace = 2.5,
		MinSecondsPerInput = 0.08,
	},
	-- AI Model Rig: press while the loss needle is in the green zone. Later epochs are faster and tighter.
	TrainingRun = {
		Epochs = {
			{ Speed = 0.45, ZoneWidth = 0.3 },
			{ Speed = 0.6, ZoneWidth = 0.24 },
			{ Speed = 0.75, ZoneWidth = 0.19 },
			{ Speed = 0.95, ZoneWidth = 0.15 },
		},
		EpochSeconds = 6,
		MaxLag = 0.5,
		Lead = 0.05,
	},
}

-- Countdown: starts at TimeLimit. A clean prompt (accuracy >= CleanAccuracy) adds
-- CleanBonus + BonusPerPrompt * (n - 1) seconds; a sloppy one removes ErrorPenalty.
GameConfig.BURST_RULES = {
	TimeLimit = 12,
	LatencyGrace = 0.5,
	MaxCharsPerSecond = 20,
	ForgivenEditsPerBurst = 0,
	CleanAccuracy = 0.9,
	CleanBonus = 6,
	BonusPerPrompt = 2,
	ErrorPenalty = 1.5,
}

-- Deploy battle: a Galaga-style shooter. Bugs enter from the top, hold formation, then dive at YOUR CODE.
-- Your app fires automatically; move to aim. Each missing quality point (S=3 ... C=0 average) adds
-- ExtraBugsPerMissingQuality bugs to every wave. Station grades set the loadout (LoadoutComponents).
GameConfig.BATTLE_RULES = {
	Waves = {
		{ Count = 6, Interval = 0.9, DiveDelay = 5, DiveSpacing = 1.1, DiveTime = 3.2 },
		{ Count = 9, Interval = 0.7, DiveDelay = 4, DiveSpacing = 0.85, DiveTime = 2.6 },
	},
	FirstBugDelay = 1.5,
	WaveGap = 2.5,
	EntryTime = 1.2,
	VisibleDelay = 0.3,
	ExtraBugsPerMissingQuality = 1,
	BossHp = 14,
	BossEntryTime = 2,
	BossHoldTime = 4,
	BossTravel = 14,
	BossMinionInterval = 2.5,
	BossMinionDiveTime = 2.8,
	LatencyGrace = 0.3,
	MoodHitPenalty = 15,
	BossHitPenalty = 40,
	MaxDuration = 150,
	BaseFireInterval = 0.32,
	FireIntervalPerQuality = 0.05, -- an all-S Server Rack fires every 0.17s
	ShotBudgetSlack = 4,
	RollbackMood = 50,
	RollbackMinQuality = 2, -- Database Console averaging A or better
	HomingMinQuality = 2, -- AI Model Rig averaging A or better
	LoadoutComponents = {
		Shield = "FrontendUnits",
		FireRate = "BackendEndpoints",
		Rollback = "DatabaseTables",
		Homing = "PromptTokens",
	},
}

-- Time of day: one full day every DayLengthSeconds, starting at StartClock (24h). Night runs about 18:00-06:00.
GameConfig.DAY_CYCLE = {
	DayLengthSeconds = 720,
	StartClock = 9,
}

-- Act 2 ends when valuation reaches its starting value plus this step.
export type Milestone = {
	Id: string,
	Kind: "Hires" | "ActDeploys" | "GoalProgress",
	At: number, -- hires owned, deploys shipped this act, or the fraction of the valuation goal reached
	Title: string,
	Body: string,
}

-- Act 2 is long on purpose, so it's broken into milestones the player can see coming. The ActDeploys ones line
-- up with when the act's clients unlock.
GameConfig.ACT2 = {
	ValuationStep = 1.5,
	Milestones = {
		{ Id = "FirstHire", Kind = "Hires", At = 1, Title = "FIRST HIRE!", Body = "Somebody else can write the bugs now." },
		{ Id = "PixelForge", Kind = "ActDeploys", At = 2, Title = "NEW CLIENT", Body = "PixelForge Indie Studio wants a game." },
		{ Id = "BrewCrew", Kind = "ActDeploys", At = 4, Title = "NEW CLIENT", Body = "BrewCrew Coffee Rewards wants an app." },
		{ Id = "Halfway", Kind = "GoalProgress", At = 0.5, Title = "HALFWAY THERE", Body = "Investors are starting to call back." },
	} :: { Milestone },
}

-- Deploy battle difficulty per act, applied on top of BATTLE_RULES.
GameConfig.ACT_BATTLE = {
	[2] = { ExtraBugsPerWave = 2, DiveTimeScale = 0.85, BossHp = 20 },
} :: { [number]: { ExtraBugsPerWave: number, DiveTimeScale: number, BossHp: number } }

-- Published cutscene animation ids (see docs/animations-publish-checklist.md). 0 = not published yet, and
-- Actors falls back to a built-in animation or none.
GameConfig.ANIMATIONS = {
	LaptopClose = 108241364195484,
	HandOverCash = 123450171428287,
	CountCash = 106883020920845,
	Talk = 108929071791744,
	SitCouch = 75760978448748,
	DeskType = 84458442587066 ,
} :: { [string]: number }

GameConfig.STARTING_VALUATION = 1.0
GameConfig.RENT_GOAL = 750
GameConfig.MAX_PLAYERS = 6
GameConfig.MAX_REMOTE_STRING = 200

GameConfig.SAVE = {
	DataStoreName = "VibecoderSave_v1",
	KeyPrefix = "player_",
	AutosaveInterval = 60,
	LockStaleAfter = 120,
	MaxLoadRetries = 3,
}

return GameConfig
