--!strict
-- All tunable numbers live here. Code reads from this table and never hard-codes values.

export type ClientDef = {
	Id: string,
	Name: string,
	Project: string,
	TierMultiplier: number,
	UnlockAtDeploys: number,
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
} :: { [string]: { [string]: number } }

GameConfig.CLIENTS = {
	{ Id = "PawsAndSuds", Name = "Paws & Suds Grooming", Project = "LandingPage", TierMultiplier = 20, UnlockAtDeploys = 0 },
	{ Id = "RollingTaco", Name = "Rolling Taco Truck", Project = "LandingPage", TierMultiplier = 30, UnlockAtDeploys = 2 },
	{ Id = "CornerBakery", Name = "Corner Bakery", Project = "LandingPage", TierMultiplier = 40, UnlockAtDeploys = 4 },
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

-- Battle countdown works like the burst one; CleanPromptAccuracy decides what counts as clean.
GameConfig.BATTLE_RULES = {
	ShipPromptsRequired = 4,
	TimeLimit = 25,
	CleanBonus = 8,
	BonusPerPrompt = 2,
	ErrorPenalty = 2,
	BugTravelTime = 6,
	FirstBugDelay = 2,
	LatencyGrace = 0.25,
	MoodHitPenalty = 15,
	BadPromptPenalty = 5,
	MissedSquashPenalty = 3,
	MinPromptAccuracy = 0.6,
	CleanPromptAccuracy = 0.9,
	MaxDuration = 120,
	MaxCharsPerSecond = 20,
}

GameConfig.STARTING_VALUATION = 1.0
GameConfig.RENT_GOAL = 1500
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
