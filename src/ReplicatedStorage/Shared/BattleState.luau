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

-- Act 2 squad rules (GameConfig.SQUAD); declared here because pure modules cannot require GameConfig.
export type WeaponRules = { Role: string, Interval: number, PerShot: number }

export type SquadRules = {
	ShipY: number,
	ShipMaxSpeed: number,
	ShipSlack: number,
	HitRadius: number,
	WingShieldRecharge: number,
	Weapons: { Spread: WeaponRules, Beam: WeaponRules, Missile: WeaponRules },
	ShieldRole: string,
}

export type SquadOptions = {
	Wingmen: { string }, -- hired roles, each flying a wingman
	EnemyKind: ("Crash" | "Lag")?,
	BossVolleys: boolean,
	Squad: SquadRules,
}

export type Weapon = "Ship" | "Spread" | "Beam" | "Missile"
export type ShipSample = { T: number, X: number }

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
	WeaponShots: { [string]: number }, -- kills claimed per Weapon
	ShipSamples: { ShipSample }, -- the last 2 s of ship positions, oldest first
	SlowUntil: number,
	WingShieldReadyAt: number,
	Options: SquadOptions?, -- nil in Act 1
	Rng: () -> number,
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
local SHIP_MIN_X = 0.04
local SHIP_MAX_X = 0.96
local SHIP_HISTORY = 2
local SLOW_SPEED_SCALE = 0.5

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

-- A copy of the rules tuned for an act: more bugs per wave, faster dives, a tougher boss.
function BattleState.RulesForAct(
	base: BattleRules,
	overrides: { ExtraBugsPerWave: number, DiveTimeScale: number, BossHp: number }?
): BattleRules
	local rules = table.clone(base)
	local waves: { WaveRules } = {}
	for _, wave in base.Waves do
		table.insert(waves, table.clone(wave))
	end
	rules.Waves = waves
	if overrides then
		for _, wave in rules.Waves do
			wave.Count += overrides.ExtraBugsPerWave
			wave.DiveTime *= overrides.DiveTimeScale
		end
		rules.BossMinionDiveTime *= overrides.DiveTimeScale
		rules.BossHp = overrides.BossHp
	end
	return rules
end

function BattleState.New(
	startTime: number,
	avgQuality: number,
	loadout: Loadout,
	rules: BattleRules,
	rng: () -> number,
	options: SquadOptions?
): Battle
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
		WeaponShots = {},
		ShipSamples = {},
		SlowUntil = startTime,
		WingShieldReadyAt = startTime,
		Options = options,
		Rng = rng,
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

local function hurt(b: Battle, penalty: number)
	b.Mood -= penalty
	b.Combo = 0
	if b.Mood <= 0 and b.RollbackAvailable then
		b.RollbackAvailable = false
		b.RollbackUsed = true
		b.Mood = b.Rules.RollbackMood
	end
end

-- One hit on the player (a landing minion, later bullets and lag): loadout Shield first, then the shield
-- wingman if hired and charged, else mood. Shields keep the streak alive.
local function takeHit(b: Battle, now: number, penalty: number)
	if b.Shield > 0 then
		b.Shield -= 1
		return
	end
	local options = b.Options
	if options and now >= b.WingShieldReadyAt and table.find(options.Wingmen, options.Squad.ShieldRole) then
		b.WingShieldReadyAt = now + options.Squad.WingShieldRecharge
		return
	end
	hurt(b, penalty)
end

function BattleState.Tick(b: Battle, now: number)
	if b.Status ~= "Running" then
		return
	end
	for _, bug in b.Bugs do
		if bug.State == "Pending" and now > bug.ReachAt + b.Rules.LatencyGrace then
			bug.State = "Hit"
			b.Mistakes += 1
			if bug.Kind == "Minion" then
				takeHit(b, now, b.Rules.MoodHitPenalty)
			else
				hurt(b, b.Rules.BossHitPenalty) -- no shield stops the boss
			end
		end
	end
	if now > b.StartTime + b.Rules.MaxDuration then
		b.Status = "Failed"
		return
	end
	settle(b)
end

-- The client streams its ship x. Clamped to the field and to how far the ship could have flown since the last
-- sample (half speed while slowed), so a teleporting client gets nowhere. Act 1 has no ship hitbox.
function BattleState.MoveShip(b: Battle, x: number, now: number)
	local options = b.Options
	if not options or x ~= x then
		return
	end
	local squad = options.Squad
	local samples = b.ShipSamples
	x = math.clamp(x, SHIP_MIN_X, SHIP_MAX_X)
	local last = samples[#samples]
	if last then
		local speed = squad.ShipMaxSpeed * (if now < b.SlowUntil then SLOW_SPEED_SCALE else 1)
		local reach = speed * math.max(now - last.T, 0) + squad.ShipSlack
		x = math.clamp(x, last.X - reach, last.X + reach)
	end
	table.insert(samples, { T = now, X = x })
	while samples[1].T < now - SHIP_HISTORY do
		table.remove(samples, 1)
	end
end

-- Where the ship was at time t: the latest sample at or before t, else the oldest one, else mid-field.
function BattleState.ShipXAt(b: Battle, t: number): number
	local samples = b.ShipSamples
	local x = if samples[1] then samples[1].X else 0.5
	for _, sample in samples do
		if sample.T > t then
			break
		end
		x = sample.X
	end
	return x
end

-- Fire interval and kills per volley for a weapon, or nil if the battle doesn't have it (a wingman needs its hire).
local function weaponRate(b: Battle, weapon: Weapon): (number?, number)
	if weapon == "Ship" then
		return b.FireInterval, 1
	end
	local options = b.Options
	if not options then
		return nil, 0
	end
	local weapons = options.Squad.Weapons
	local rules = if weapon == "Spread"
		then weapons.Spread
		elseif weapon == "Beam" then weapons.Beam
		elseif weapon == "Missile" then weapons.Missile
		else nil
	if not rules or not table.find(options.Wingmen, rules.Role) then
		return nil, 0
	end
	return rules.Interval, rules.PerShot
end

-- A shot hit a bug (the client reports the bug id and weapon, Ship by default). Valid only if the bug is on screen
-- and not yet landed, and that weapon can't have fired more shots than its rate allows.
function BattleState.Kill(b: Battle, bugId: number, now: number, weapon: Weapon?): boolean
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
	local chosen: Weapon = weapon or "Ship"
	local interval, perShot = weaponRate(b, chosen)
	if not interval then
		return false
	end
	local shotsFired = math.floor((now - b.StartTime) / interval) * perShot + rules.ShotBudgetSlack
	local used = b.WeaponShots[chosen] or 0
	if used >= shotsFired then
		return false
	end

	b.WeaponShots[chosen] = used + 1
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
