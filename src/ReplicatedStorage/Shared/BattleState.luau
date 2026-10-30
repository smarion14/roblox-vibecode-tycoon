--!strict
-- Pure: no requires, no Roblox APIs. Deterministic deploy-battle simulation the server runs on its own clock.
-- The battle is bugs only: regular waves, then a boss whose phrase is typed word by word. Clock and RNG are passed in.

export type WaveRules = {
	Count: number,
	Interval: number,
	Travel: number,
}

export type BattleRules = {
	Waves: { WaveRules },
	FirstBugDelay: number,
	WaveGap: number,
	ExtraBugsPerMissingQuality: number,
	BossTravel: number,
	BossMinionInterval: number,
	BossMinionTravel: number,
	LatencyGrace: number,
	MoodHitPenalty: number,
	BossHitPenalty: number,
	MissedSquashPenalty: number,
	MaxDuration: number,
	MaxCharsPerSecond: number,
}

export type BugState = "Pending" | "Squashed" | "Hit"
export type BugKind = "Minion" | "Boss"
export type BattleStatus = "Running" | "Shipped" | "Failed"

export type Bug = {
	Id: number,
	Kind: BugKind,
	Wave: number,
	Word: string,
	Words: { string },
	Hp: number,
	Side: number,
	SpawnAt: number,
	ReachAt: number,
	LastHitAt: number,
	State: BugState,
}

export type Battle = {
	StartTime: number,
	Mood: number,
	Combo: number,
	MaxCombo: number,
	Squashed: number,
	Successes: number,
	Mistakes: number,
	Bugs: { Bug },
	Status: BattleStatus,
	Rules: BattleRules,
}

export type BattleResult = {
	Status: BattleStatus,
	MoodRatio: number,
	Accuracy: number,
	MaxCombo: number,
	Successes: number, -- squashes plus boss word hits
	Mistakes: number, -- missed squashes plus bugs that reached your code
}

export type BattleSnapshot = {
	Mood: number,
	Combo: number,
	Progress: number,
	BugStates: { [number]: BugState },
	BossHp: number,
	Status: BattleStatus,
}

local BASE_MOOD = 70
local MOOD_PER_QUALITY = 10
local MAX_MOOD = 100
local MAX_QUALITY = 3

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

local function addBug(
	bugs: { Bug },
	kind: BugKind,
	wave: number,
	words: { string },
	side: number,
	spawnAt: number,
	travel: number
)
	table.insert(bugs, {
		Id = #bugs + 1,
		Kind = kind,
		Wave = wave,
		Word = table.concat(words, " "),
		Words = words,
		Hp = #words,
		Side = side,
		SpawnAt = spawnAt,
		ReachAt = spawnAt + travel,
		LastHitAt = spawnAt,
		State = "Pending",
	})
end

-- The battle ends once nothing is left pending: shipped if the client is still on the call.
local function settle(b: Battle)
	if b.Status ~= "Running" then
		return
	end
	if b.Mood <= 0 then
		b.Status = "Failed"
		return
	end
	for _, bug in b.Bugs do
		if bug.State == "Pending" then
			return
		end
	end
	b.Status = "Shipped"
end

function BattleState.New(
	startTime: number,
	avgQuality: number,
	bugWords: { string },
	bossPhrase: string,
	rules: BattleRules,
	rng: () -> number
): Battle
	local bugs: { Bug } = {}
	local extraBugs = math.floor((MAX_QUALITY - math.clamp(avgQuality, 0, MAX_QUALITY)) * rules.ExtraBugsPerMissingQuality)

	local spawnAt = startTime + rules.FirstBugDelay
	for waveIndex, wave in rules.Waves do
		for _ = 1, wave.Count + extraBugs do
			local word = pick(bugWords, rng())
			local side = if rng() < 0.5 then -1 else 1
			addBug(bugs, "Minion", waveIndex, { word }, side, spawnAt, wave.Travel)
			spawnAt += wave.Interval
		end
		spawnAt += rules.WaveGap
	end

	-- Boss wave: one slow bug carrying a phrase, escorted by minions that all land before it does,
	-- so the last moment of the battle is the boss alone.
	local bossWave = #rules.Waves + 1
	local bossSpawn = spawnAt
	addBug(bugs, "Boss", bossWave, string.split(bossPhrase, " "), if rng() < 0.5 then -1 else 1, bossSpawn, rules.BossTravel)
	local minionSpawn = bossSpawn + rules.BossMinionInterval
	while minionSpawn + rules.BossMinionTravel < bossSpawn + rules.BossTravel do
		local word = pick(bugWords, rng())
		local side = if rng() < 0.5 then -1 else 1
		addBug(bugs, "Minion", bossWave, { word }, side, minionSpawn, rules.BossMinionTravel)
		minionSpawn += rules.BossMinionInterval
	end

	return {
		StartTime = startTime,
		Mood = math.clamp(BASE_MOOD + MOOD_PER_QUALITY * avgQuality, BASE_MOOD, MAX_MOOD),
		Combo = 0,
		MaxCombo = 0,
		Squashed = 0,
		Successes = 0,
		Mistakes = 0,
		Bugs = bugs,
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
			b.Mistakes += 1
			b.Mood -= if bug.Kind == "Boss" then b.Rules.BossHitPenalty else b.Rules.MoodHitPenalty
			b.Combo = 0
		end
	end

	if now > b.StartTime + b.Rules.MaxDuration then
		b.Status = "Failed"
		return
	end
	settle(b)
end

-- A word can't be typed faster than the typing cap allows after its target appears (or after the last boss hit).
local function reachable(bug: Bug, word: string, now: number, rules: BattleRules): boolean
	local earliest = bug.LastHitAt + #word / rules.MaxCharsPerSecond
	return bug.State == "Pending" and earliest <= now and now <= bug.ReachAt + rules.LatencyGrace
end

function BattleState.Squash(b: Battle, word: string, now: number): boolean
	BattleState.Tick(b, now)
	if b.Status ~= "Running" then
		return false
	end

	local wanted = normalizeWord(word)
	local rules = b.Rules

	-- Boss first: its next unbroken word.
	for _, bug in b.Bugs do
		if bug.Kind == "Boss" and bug.State == "Pending" then
			local nextWord = bug.Words[#bug.Words - bug.Hp + 1]
			if nextWord == wanted and reachable(bug, wanted, now, rules) then
				bug.Hp -= 1
				bug.LastHitAt = now
				b.Successes += 1
				bumpCombo(b)
				if bug.Hp <= 0 then
					bug.State = "Squashed"
					b.Squashed += 1
				end
				settle(b)
				return true
			end
		end
	end

	for _, bug in b.Bugs do
		if bug.Kind == "Minion" and bug.Word == wanted and reachable(bug, wanted, now, rules) then
			bug.State = "Squashed"
			b.Squashed += 1
			b.Successes += 1
			bumpCombo(b)
			settle(b)
			return true
		end
	end

	b.Combo = 0
	b.Mistakes += 1
	b.Mood -= rules.MissedSquashPenalty
	settle(b)
	return false
end

function BattleState.Result(b: Battle): BattleResult
	return {
		Status = b.Status,
		MoodRatio = math.max(b.Mood, 0) / MAX_MOOD,
		Accuracy = b.Squashed / math.max(#b.Bugs, 1),
		MaxCombo = b.MaxCombo,
		Successes = b.Successes,
		Mistakes = b.Mistakes,
	}
end

function BattleState.Snapshot(b: Battle): BattleSnapshot
	local bugStates: { [number]: BugState } = {}
	local resolved = 0
	local bossHp = 0
	for _, bug in b.Bugs do
		bugStates[bug.Id] = bug.State
		if bug.State ~= "Pending" then
			resolved += 1
		end
		if bug.Kind == "Boss" then
			bossHp = bug.Hp
		end
	end
	return {
		Mood = b.Mood,
		Combo = b.Combo,
		Progress = resolved / math.max(#b.Bugs, 1),
		BugStates = bugStates,
		BossHp = bossHp,
		Status = b.Status,
	}
end

return BattleState
