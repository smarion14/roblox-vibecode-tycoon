--!strict
-- Pure: no requires, no Roblox APIs. The deploy battle as a Galaga-style shooter, simulated by the server on its
-- own clock. Bugs fly deterministic paths (BugPosition), so the client draws exactly what the server judges.
-- Bugs enter from the top, hover in formation, then dive at YOUR CODE (the bottom). Shoot them before they land.
-- Station part grades become the ship loadout (shield, fire rate, rollback, homing).

export type WaveRules = {
	Count: number,
	Interval: number, -- seconds between bugs entering
	DiveDelay: number, -- seconds after the wave starts before the first bug dives
	DiveSpacing: number, -- seconds between dives
	DiveTime: number, -- seconds a dive takes to reach the bottom
}

export type BattleRules = {
	Waves: { WaveRules },
	FirstBugDelay: number,
	WaveGap: number,
	EntryTime: number,
	VisibleDelay: number,
	ExtraBugsPerMissingQuality: number,
	BossHp: number,
	BossEntryTime: number,
	BossHoldTime: number,
	BossTravel: number,
	BossMinionInterval: number,
	BossMinionDiveTime: number,
	LatencyGrace: number,
	MoodHitPenalty: number,
	BossHitPenalty: number,
	MaxDuration: number,
	BaseFireInterval: number,
	FireIntervalPerQuality: number,
	ShotBudgetSlack: number,
	RollbackMood: number,
	RollbackMinQuality: number,
	HomingMinQuality: number,
	LoadoutComponents: { Shield: string, FireRate: string, Rollback: string, Homing: string },
}

-- shortcut: duplicated from Economy, pure modules cannot require each other; unify if require-by-string is adopted
export type GradeCounts = { S: number, A: number, B: number, C: number }

export type Loadout = {
	Shield: number, -- bug hits absorbed before mood takes damage
	FireInterval: number, -- seconds between shots
	Rollback: boolean, -- one save from failing
	Homing: boolean, -- client-side aim assist
}

export type BugState = "Pending" | "Squashed" | "Hit"
export type BugKind = "Minion" | "Boss"
export type BattleStatus = "Running" | "Shipped" | "Failed"

export type Bug = {
	Id: number,
	Kind: BugKind,
	Wave: number,
	Side: number,
	SpawnAt: number,
	EntryTime: number,
	SpawnX: number,
	FormX: number,
	FormY: number,
	DiveAt: number,
	DiveX: number,
	ReachAt: number,
	Hp: number,
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
	Shield: number,
	RollbackAvailable: boolean,
	RollbackUsed: boolean,
	FireInterval: number,
	ShotsUsed: number,
	LastKillAt: number,
	Bugs: { Bug },
	Status: BattleStatus,
	Rules: BattleRules,
}

export type BattleResult = {
	Status: BattleStatus,
	MoodRatio: number,
	Accuracy: number,
	MaxCombo: number,
	Successes: number, -- bugs shot plus boss hits
	Mistakes: number, -- bugs that reached your code
}

export type BattleSnapshot = {
	Mood: number,
	Combo: number,
	Progress: number,
	BugStates: { [number]: BugState },
	BossHp: number,
	Shield: number,
	RollbackUsed: boolean,
	Status: BattleStatus,
}

local BASE_MOOD = 70
local MOOD_PER_QUALITY = 10
local MAX_MOOD = 100
local MAX_QUALITY = 3
local GRADE_VALUE = { S = 3, A = 2, B = 1, C = 0 }
local SWAY = 0.025
local FORMATION_ROWS = 3

local BattleState = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 2
end

local function averageQuality(grades: GradeCounts?): number
	if not grades then
		return 0
	end
	local count = grades.S + grades.A + grades.B + grades.C
	if count == 0 then
		return 0
	end
	return (grades.S * GRADE_VALUE.S + grades.A * GRADE_VALUE.A + grades.B * GRADE_VALUE.B) / count
end

-- Each station's average grade buys one ship upgrade.
function BattleState.LoadoutFrom(inventory: { [string]: GradeCounts }, rules: BattleRules): Loadout
	local parts = rules.LoadoutComponents
	return {
		Shield = math.floor(averageQuality(inventory[parts.Shield])),
		FireInterval = rules.BaseFireInterval - rules.FireIntervalPerQuality * averageQuality(inventory[parts.FireRate]),
		Rollback = averageQuality(inventory[parts.Rollback]) >= rules.RollbackMinQuality,
		Homing = averageQuality(inventory[parts.Homing]) >= rules.HomingMinQuality,
	}
end

-- Where a bug is (x across, y down, both roughly 0-1) at a given time. Shared by server and client.
function BattleState.BugPosition(bug: Bug, t: number): (number, number)
	local entry = math.clamp((t - bug.SpawnAt) / bug.EntryTime, 0, 1)
	if bug.Kind == "Boss" then
		if entry < 1 then
			return 0.5, lerp(-0.15, bug.FormY, easeOut(entry))
		end
		local x = 0.5 + 0.22 * math.sin(0.9 * (t - bug.SpawnAt))
		if t < bug.DiveAt then
			return x, bug.FormY
		end
		return x, lerp(bug.FormY, 1.05, math.clamp((t - bug.DiveAt) / (bug.ReachAt - bug.DiveAt), 0, 1))
	end

	if entry < 1 then
		local eased = easeOut(entry)
		return lerp(bug.SpawnX, bug.FormX, eased) + 0.12 * bug.Side * math.sin(math.pi * entry), lerp(-0.1, bug.FormY, eased)
	end
	local function swayX(at: number): number
		return bug.FormX + SWAY * math.sin(2 * math.pi * 0.4 * at + bug.Id)
	end
	if t < bug.DiveAt then
		return swayX(t), bug.FormY
	end
	local dive = math.clamp((t - bug.DiveAt) / (bug.ReachAt - bug.DiveAt), 0, 1)
	local x = lerp(swayX(bug.DiveAt), bug.DiveX, dive) + 0.15 * bug.Side * math.sin(math.pi * dive)
	return x, lerp(bug.FormY, 1.05, dive ^ 1.4)
end

function BattleState.New(startTime: number, avgQuality: number, loadout: Loadout, rules: BattleRules, rng: () -> number): Battle
	local bugs: { Bug } = {}
	local extraBugs = math.floor((MAX_QUALITY - math.clamp(avgQuality, 0, MAX_QUALITY)) * rules.ExtraBugsPerMissingQuality)

	local function addMinion(wave: number, slot: number, spawnAt: number, diveAt: number, diveTime: number)
		table.insert(bugs, {
			Id = #bugs + 1,
			Kind = "Minion",
			Wave = wave,
			Side = if rng() < 0.5 then -1 else 1,
			SpawnAt = spawnAt,
			EntryTime = rules.EntryTime,
			SpawnX = rng(),
			FormX = 0.12 + rng() * 0.76,
			FormY = 0.12 + ((slot - 1) % FORMATION_ROWS) * 0.09,
			DiveAt = diveAt,
			DiveX = 0.1 + rng() * 0.8,
			ReachAt = diveAt + diveTime,
			Hp = 1,
			State = "Pending",
		})
	end

	local waveStart = startTime + rules.FirstBugDelay
	for waveIndex, wave in rules.Waves do
		local count = wave.Count + extraBugs
		for slot = 1, count do
			local spawnAt = waveStart + (slot - 1) * wave.Interval
			local diveAt = math.max(waveStart + wave.DiveDelay + (slot - 1) * wave.DiveSpacing, spawnAt + rules.EntryTime + 0.3)
			addMinion(waveIndex, slot, spawnAt, diveAt, wave.DiveTime)
		end
		waveStart += wave.DiveDelay + (count - 1) * wave.DiveSpacing + rules.WaveGap
	end

	-- Boss wave: one big bug that holds at the top, then slowly descends; escorts dive while it does.
	local bossWave = #rules.Waves + 1
	local bossSpawn = waveStart
	local descendAt = bossSpawn + rules.BossEntryTime + rules.BossHoldTime
	local bossReach = descendAt + rules.BossTravel
	table.insert(bugs, {
		Id = #bugs + 1,
		Kind = "Boss",
		Wave = bossWave,
		Side = 1,
		SpawnAt = bossSpawn,
		EntryTime = rules.BossEntryTime,
		SpawnX = 0.5,
		FormX = 0.5,
		FormY = 0.15,
		DiveAt = descendAt,
		DiveX = 0.5,
		ReachAt = bossReach,
		Hp = rules.BossHp,
		State = "Pending",
	})
	local escortSpawn = bossSpawn + rules.BossMinionInterval
	local slot = 1
	-- Escorts all land before the boss does, so the last moment is the boss alone.
	while escortSpawn + rules.EntryTime + 0.8 + rules.BossMinionDiveTime < bossReach - 1 do
		addMinion(bossWave, slot, escortSpawn, escortSpawn + rules.EntryTime + 0.8, rules.BossMinionDiveTime)
		escortSpawn += rules.BossMinionInterval
		slot += 1
	end

	return {
		StartTime = startTime,
		Mood = math.clamp(BASE_MOOD + MOOD_PER_QUALITY * avgQuality, BASE_MOOD, MAX_MOOD),
		Combo = 0,
		MaxCombo = 0,
		Squashed = 0,
		Successes = 0,
		Mistakes = 0,
		Shield = loadout.Shield,
		RollbackAvailable = loadout.Rollback,
		RollbackUsed = false,
		FireInterval = loadout.FireInterval,
		ShotsUsed = 0,
		LastKillAt = startTime,
		Bugs = bugs,
		Status = "Running",
		Rules = rules,
	}
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

function BattleState.Tick(b: Battle, now: number)
	if b.Status ~= "Running" then
		return
	end
	for _, bug in b.Bugs do
		if bug.State == "Pending" and now > bug.ReachAt + b.Rules.LatencyGrace then
			bug.State = "Hit"
			b.Mistakes += 1
			if b.Shield > 0 and bug.Kind == "Minion" then
				b.Shield -= 1 -- the shield eats the hit; the streak survives
			else
				b.Mood -= if bug.Kind == "Boss" then b.Rules.BossHitPenalty else b.Rules.MoodHitPenalty
				b.Combo = 0
				if b.Mood <= 0 and b.RollbackAvailable then
					b.RollbackAvailable = false
					b.RollbackUsed = true
					b.Mood = b.Rules.RollbackMood
				end
			end
		end
	end
	if now > b.StartTime + b.Rules.MaxDuration then
		b.Status = "Failed"
		return
	end
	settle(b)
end

-- A shot hit a bug (the client reports the bug id). Valid only if the bug is on screen and not yet landed,
-- and the player can't have fired more shots than their fire rate allows.
function BattleState.Kill(b: Battle, bugId: number, now: number): boolean
	BattleState.Tick(b, now)
	if b.Status ~= "Running" then
		return false
	end
	local bug = b.Bugs[bugId]
	local rules = b.Rules
	if not bug or bug.State ~= "Pending" then
		return false
	end
	if now < bug.SpawnAt + rules.VisibleDelay or now > bug.ReachAt + rules.LatencyGrace then
		return false
	end
	local shotsFired = math.floor((now - b.StartTime) / b.FireInterval) + rules.ShotBudgetSlack
	if b.ShotsUsed >= shotsFired then
		return false
	end

	b.ShotsUsed += 1
	b.Successes += 1
	b.Combo += 1
	b.MaxCombo = math.max(b.MaxCombo, b.Combo)
	b.LastKillAt = math.max(b.LastKillAt, now)
	bug.Hp -= 1
	if bug.Hp <= 0 then
		bug.State = "Squashed"
		b.Squashed += 1
	end
	settle(b)
	return true
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
		Shield = b.Shield,
		RollbackUsed = b.RollbackUsed,
		Status = b.Status,
	}
end

return BattleState
