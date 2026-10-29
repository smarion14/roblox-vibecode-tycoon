--!strict
-- Pure: no requires, no Roblox APIs. Deterministic deploy-battle simulation the server runs on its own clock.
-- Clock, RNG and the typing judge are passed in.

export type BattleRules = {
	ShipPromptsRequired: number,
	BugTravelTime: number,
	FirstBugDelay: number,
	LatencyGrace: number,
	MoodHitPenalty: number,
	BadPromptPenalty: number,
	MinPromptAccuracy: number,
	CleanPromptAccuracy: number,
	MaxDuration: number,
	MaxCharsPerSecond: number,
}

export type Judge = {
	Accuracy: (expected: string, typed: string, forgivenEdits: number) -> number,
	IsPlausible: (charCount: number, elapsed: number, maxCharsPerSecond: number) -> boolean,
}

export type BugState = "Pending" | "Squashed" | "Hit"
export type BattleStatus = "Running" | "Shipped" | "Failed"

export type Bug = {
	Id: number,
	Word: string,
	Side: number,
	SpawnAt: number,
	ReachAt: number,
	State: BugState,
}

export type Battle = {
	StartTime: number,
	Mood: number,
	Combo: number,
	MaxCombo: number,
	Progress: number,
	PromptIndex: number,
	PromptIssuedAt: number,
	Prompts: { string },
	Bugs: { Bug },
	AccuracySum: number,
	PromptsJudged: number,
	Status: BattleStatus,
	Rules: BattleRules,
}

export type BattleResult = {
	Status: BattleStatus,
	MoodRatio: number,
	Accuracy: number,
	MaxCombo: number,
}

export type BattleSnapshot = {
	Mood: number,
	Combo: number,
	Progress: number,
	PromptText: string,
	BugStates: { [number]: BugState },
	Status: BattleStatus,
	PromptsJudged: number,
}

local BASE_MOOD = 70
local MOOD_PER_QUALITY = 10
local MAX_MOOD = 100
local BASE_SPAWN_INTERVAL = 1.6
local SPAWN_INTERVAL_PER_QUALITY = 0.3

local BattleState = {}

local function normalizeWord(word: string): string
	return (string.match(string.lower(word), "^%s*(.-)%s*$") or "")
end

local function pick<T>(list: { T }, roll: number): T
	return list[math.clamp(math.floor(roll * #list) + 1, 1, #list)]
end

local function bumpCombo(b: Battle)
	b.Combo += 1
	b.MaxCombo = math.max(b.MaxCombo, b.Combo)
end

function BattleState.New(
	startTime: number,
	avgQuality: number,
	prompts: { string },
	bugWords: { string },
	rules: BattleRules,
	rng: () -> number
): Battle
	local bugs: { Bug } = {}
	local interval = BASE_SPAWN_INTERVAL + SPAWN_INTERVAL_PER_QUALITY * avgQuality
	local spawnAt = startTime + rules.FirstBugDelay
	while spawnAt <= startTime + rules.MaxDuration do
		local word = pick(bugWords, rng())
		local side = if rng() < 0.5 then -1 else 1
		table.insert(bugs, {
			Id = #bugs + 1,
			Word = word,
			Side = side,
			SpawnAt = spawnAt,
			ReachAt = spawnAt + rules.BugTravelTime,
			State = "Pending",
		})
		spawnAt += interval
	end

	return {
		StartTime = startTime,
		Mood = math.clamp(BASE_MOOD + MOOD_PER_QUALITY * avgQuality, BASE_MOOD, MAX_MOOD),
		Combo = 0,
		MaxCombo = 0,
		Progress = 0,
		PromptIndex = 1,
		PromptIssuedAt = startTime,
		Prompts = prompts,
		Bugs = bugs,
		AccuracySum = 0,
		PromptsJudged = 0,
		Status = "Running",
		Rules = rules,
	}
end

function BattleState.Tick(b: Battle, now: number)
	if b.Status ~= "Running" then
		return
	end

	for _, bug in b.Bugs do
		if bug.State == "Pending" and now > bug.ReachAt + b.Rules.LatencyGrace then
			bug.State = "Hit"
			b.Mood -= b.Rules.MoodHitPenalty
			b.Combo = 0
		end
	end

	if b.Mood <= 0 or now > b.StartTime + b.Rules.MaxDuration then
		b.Status = "Failed"
	end
end

function BattleState.Squash(b: Battle, word: string, now: number): boolean
	BattleState.Tick(b, now)
	if b.Status ~= "Running" then
		return false
	end

	local wanted = normalizeWord(word)
	for _, bug in b.Bugs do
		if
			bug.State == "Pending"
			and bug.Word == wanted
			and bug.SpawnAt <= now
			and now <= bug.ReachAt + b.Rules.LatencyGrace
		then
			bug.State = "Squashed"
			bumpCombo(b)
			return true
		end
	end

	b.Combo = 0
	return false
end

function BattleState.SubmitPrompt(b: Battle, text: string, now: number, judge: Judge): number
	BattleState.Tick(b, now)
	if b.Status ~= "Running" then
		return 0
	end

	local rules = b.Rules
	local prompt = b.Prompts[b.PromptIndex]
	local accuracy = 0
	if judge.IsPlausible(#text, now - b.PromptIssuedAt, rules.MaxCharsPerSecond) then
		accuracy = judge.Accuracy(prompt, text, 0)
	end

	if accuracy < rules.MinPromptAccuracy then
		b.Mood -= rules.BadPromptPenalty
		b.Combo = 0
	else
		if accuracy >= rules.CleanPromptAccuracy then
			bumpCombo(b)
		end
		b.Progress += 1
		b.PromptIndex = b.PromptIndex % #b.Prompts + 1
	end

	b.PromptIssuedAt = now
	b.AccuracySum += accuracy
	b.PromptsJudged += 1

	if b.Progress >= rules.ShipPromptsRequired then
		b.Status = "Shipped"
	elseif b.Mood <= 0 then
		b.Status = "Failed"
	end
	return accuracy
end

function BattleState.Result(b: Battle): BattleResult
	return {
		Status = b.Status,
		MoodRatio = math.max(b.Mood, 0) / MAX_MOOD,
		Accuracy = b.AccuracySum / math.max(b.PromptsJudged, 1),
		MaxCombo = b.MaxCombo,
	}
end

function BattleState.Snapshot(b: Battle): BattleSnapshot
	local bugStates: { [number]: BugState } = {}
	for _, bug in b.Bugs do
		bugStates[bug.Id] = bug.State
	end
	return {
		Mood = b.Mood,
		Combo = b.Combo,
		Progress = b.Progress,
		PromptText = b.Prompts[b.PromptIndex],
		BugStates = bugStates,
		Status = b.Status,
		PromptsJudged = b.PromptsJudged,
	}
end

return BattleState
