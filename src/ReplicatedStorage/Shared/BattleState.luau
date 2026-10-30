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
	ShardDiveDelay: number,
	ShardDiveTime: number,
	ShardSpread: number,
	LagRadius: number,
	LagSlowSeconds: number,
	VolleyInterval: number,
	VolleySize: number,
	VolleySpreadDegrees: number,
	BulletSpeed: number,
}

export type SquadOptions = {
	Wingmen: { string }, -- hired roles, each flying a wingman
	EnemyKind: ("Crash" | "Lag")?,
	BossVolleys: boolean,
	Squad: SquadRules,
}

export type Weapon = "Ship" | "Spread" | "Beam" | "Missile"
-- D: total distance the ship was allowed to fly from battle start to T (slack not included).
export type ShipSample = { T: number, X: number, D: number }

export type BugState = "Pending" | "Squashed" | "Hit"
export type BugKind = "Minion" | "Boss" | "Crash" | "Lag" | "Shard"
export type BattleStatus = "Running" | "Shipped" | "Failed"

-- A boss bullet flies in a straight line from its origin (see BulletPosition).
export type Bullet = {
	Id: number,
	FiredAt: number,
	OriginX: number,
	OriginY: number,
	DirX: number,
	DirY: number,
	State: "Live" | "Hit" | "Gone",
}

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
	Bullets: { Bullet }, -- boss volleys, empty unless options ask for them
	BossDiedAt: number?,
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
	BugCount: number, -- grows when crash reports split
	SlowUntil: number,
	BossDiedAt: number?,
	WingShieldReadyAt: number,
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
local SHIP_MIN_GAP = 0.05 -- samples closer than this overwrite each other, so bursts can't grow the list
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
		local startY = if bug.Kind == "Shard" then bug.FormY else -0.1 -- shards burst out where their crash died
		return lerp(bug.SpawnX, bug.FormX, eased) + 0.12 * bug.Side * math.sin(math.pi * entry), lerp(startY, bug.FormY, eased)
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

-- Where a boss bullet is at time t. Shared by server and client.
function BattleState.BulletPosition(bullet: Bullet, speed: number, t: number): (number, number)
	local travel = speed * (t - bullet.FiredAt)
	return bullet.OriginX + bullet.DirX * travel, bullet.OriginY + bullet.DirY * travel
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

	local function addMinion(wave: number, slot: number, spawnAt: number, diveAt: number, diveTime: number, kind: BugKind)
		table.insert(bugs, {
			Id = #bugs + 1,
			Kind = kind,
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

	local enemyKind: BugKind? = if options then options.EnemyKind else nil
	local waveStart = startTime + rules.FirstBugDelay
	for waveIndex, wave in rules.Waves do
		local count = wave.Count + extraBugs
		for slot = 1, count do
			local spawnAt = waveStart + (slot - 1) * wave.Interval
			local diveAt = math.max(waveStart + wave.DiveDelay + (slot - 1) * wave.DiveSpacing, spawnAt + rules.EntryTime + 0.3)
			local kind: BugKind = if enemyKind and slot % 3 == 0 then enemyKind else "Minion"
			addMinion(waveIndex, slot, spawnAt, diveAt, wave.DiveTime, kind)
		end
		waveStart += wave.DiveDelay + (count - 1) * wave.DiveSpacing + rules.WaveGap
	end

	-- Boss wave: one big bug that holds at the top, then slowly descends; escorts dive while it does.
	local bossWave = #rules.Waves + 1
	local bossSpawn = waveStart
	local descendAt = bossSpawn + rules.BossEntryTime + rules.BossHoldTime
	local bossReach = descendAt + rules.BossTravel
	local bossBug: Bug = {
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
	}
	table.insert(bugs, bossBug)
	local escortSpawn = bossSpawn + rules.BossMinionInterval
	local slot = 1
	-- Escorts all land before the boss does, so the last moment is the boss alone.
	while escortSpawn + rules.EntryTime + 0.8 + rules.BossMinionDiveTime < bossReach - 1 do
		addMinion(bossWave, slot, escortSpawn, escortSpawn + rules.EntryTime + 0.8, rules.BossMinionDiveTime, "Minion")
		escortSpawn += rules.BossMinionInterval
		slot += 1
	end

	-- Boss volleys: a fan of bullets centered straight down, from wherever the boss is when it fires.
	local bullets: { Bullet } = {}
	if options and options.BossVolleys then
		local squad = options.Squad
		local spread = math.rad(squad.VolleySpreadDegrees)
		local firedAt = bossSpawn + rules.BossEntryTime
		while firedAt < bossReach do
			local originX, originY = BattleState.BugPosition(bossBug, firedAt)
			for i = 1, squad.VolleySize do
				local angle = if squad.VolleySize > 1 then spread * ((i - 1) / (squad.VolleySize - 1) - 0.5) else 0
				table.insert(bullets, {
					Id = #bullets + 1,
					FiredAt = firedAt,
					OriginX = originX,
					OriginY = originY,
					DirX = math.sin(angle),
					DirY = math.cos(angle),
					State = "Live",
				})
			end
			firedAt += squad.VolleyInterval
		end
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
		Bullets = bullets,
		BossDiedAt = nil,
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
	local options = b.Options
	for _, bug in b.Bugs do
		if bug.State == "Pending" and now > bug.ReachAt + b.Rules.LatencyGrace then
			bug.State = "Hit"
			b.Mistakes += 1
			if bug.Kind == "Boss" then
				hurt(b, b.Rules.BossHitPenalty) -- no shield stops the boss
			elseif
				bug.Kind == "Lag"
				and options
				and math.abs(BattleState.ShipXAt(b, bug.ReachAt) - bug.DiveX) <= options.Squad.LagRadius
			then
				b.SlowUntil = math.max(b.SlowUntil, bug.ReachAt + options.Squad.LagSlowSeconds) -- a lag spike on the ship slows it instead
			else
				takeHit(b, now, b.Rules.MoodHitPenalty)
			end
		end
	end
	-- Boss bullets are judged once they cross the ship's row (plus grace), against where the ship was then.
	-- Bullets fired after the boss died were already marked Gone by Kill.
	if options then
		local squad = options.Squad
		for _, bullet in b.Bullets do
			if bullet.State ~= "Live" then
				continue
			end
			local tCross = bullet.FiredAt + (squad.ShipY - bullet.OriginY) / (bullet.DirY * squad.BulletSpeed)
			if now > tCross + b.Rules.LatencyGrace then
				local x = BattleState.BulletPosition(bullet, squad.BulletSpeed, tCross)
				if math.abs(x - BattleState.ShipXAt(b, tCross)) <= squad.HitRadius then
					bullet.State = "Hit"
					takeHit(b, now, b.Rules.MoodHitPenalty)
				else
					bullet.State = "Gone"
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

-- The client streams its ship x. Clamped to the field and to how far the ship could have flown since EVERY kept
-- sample (half speed while slowed), so slack is granted once per window, not once per message.
-- Act 1 has no ship hitbox; NaN and out-of-order times are dropped.
function BattleState.MoveShip(b: Battle, x: number, now: number)
	local options = b.Options
	local samples = b.ShipSamples
	local last = samples[#samples]
	if not options or x ~= x or now ~= now or (last and now < last.T) then
		return
	end
	local squad = options.Squad
	local speed = squad.ShipMaxSpeed * (if now < b.SlowUntil then SLOW_SPEED_SCALE else 1)
	local travel = if last then last.D + speed * (now - last.T) else 0
	local lo, hi = SHIP_MIN_X, SHIP_MAX_X
	for _, sample in samples do
		local reach = travel - sample.D + squad.ShipSlack
		lo = math.max(lo, sample.X - reach)
		hi = math.min(hi, sample.X + reach)
	end
	-- the last sample always lies inside every window; fall back to it if float error empties the range
	x = if lo <= hi then math.clamp(x, lo, hi) elseif last then last.X else x
	local sample = { T = now, X = x, D = travel }
	local previous = samples[#samples - 1]
	if previous and now - previous.T < SHIP_MIN_GAP then
		samples[#samples] = sample -- keep the older anchor, replace the in-between one
	else
		table.insert(samples, sample)
	end
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
		local options = b.Options
		if bug.Kind == "Boss" then
			b.BossDiedAt = now
			for _, bullet in b.Bullets do
				if bullet.FiredAt > now then
					bullet.State = "Gone" -- a dead boss fires nothing
				end
			end
		elseif bug.Kind == "Crash" and options then
			-- The crash report splits into two shards that burst out sideways, then dive.
			local squad = options.Squad
			local x, y = BattleState.BugPosition(bug, now)
			for _, side in { -1, 1 } do
				local diveAt = now + squad.ShardDiveDelay
				table.insert(b.Bugs, {
					Id = #b.Bugs + 1,
					Kind = "Shard",
					Wave = bug.Wave,
					Side = side,
					SpawnAt = now,
					EntryTime = 0.2,
					SpawnX = x,
					FormX = x + side * squad.ShardSpread,
					FormY = y,
					DiveAt = diveAt,
					DiveX = 0.1 + b.Rng() * 0.8,
					ReachAt = diveAt + squad.ShardDiveTime,
					Hp = 1,
					State = "Pending",
				})
			end
		end
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
		BugCount = #b.Bugs,
		SlowUntil = b.SlowUntil,
		BossDiedAt = b.BossDiedAt,
		WingShieldReadyAt = b.WingShieldReadyAt,
	}
end

return BattleState
