--!strict
-- Pure: no requires, no Roblox APIs. Act 3's deploy battle as a bullet hell, simulated by the server on its own
-- clock and replayed by the client from the same seed: New builds the whole bullet schedule from Rng(seed) and the
-- options, and BulletPosition is analytic, so both sides agree on every bullet without sending any.
-- Field: x across, y down, both 0-1; a bullet is gone once outside x/y ∈ [-0.1, 1.1] (GoneAt).
-- The caller passes cfg = GameConfig.BULLET_HELL (pure modules cannot require it).
--
-- Ship anti-cheat, Act 2's BattleState.MoveShip in 2D: every sample stores D, the total distance the ship was
-- allowed to fly since the battle began. A new position must lie within (travel - D + ShipSlack) of EVERY kept
-- sample (a 2 s window plus one older anchor), so slack is granted once per window, not once per message.
-- Reach is Euclidean (discs, not per-axis boxes), so diagonal moves get no √2 bonus. The allowed region (those
-- discs and the field box) is convex and always holds the last sample, so the ship moves from the last sample
-- toward the requested point as far as every disc allows: exact and closed-form, no iteration.
--
-- Hits are judged on a fixed 1/30 s grid from StartTime, LatencyGrace behind the server clock, so the result doesn't
-- depend on how often Tick runs. Each substep is swept: bullet and ship (ShipAt interpolates its samples) move
-- linearly across it and their closest approach is judged, so a full-speed ship can't tunnel through a bullet.
--
-- Enemies fly deterministic paths (EnemyPosition) and every bullet names the enemy that fired it (Owner). A bullet
-- flies only if its owner was active and alive when it fired (Fired), so a kill cancels the rest of an enemy's
-- schedule on both sides once the client learns the kill time. Popcorn enemies come in groups during the waves and
-- fire fans aimed at a lane or short straight streams; the ship's position isn't known when the schedule is built,
-- so "aimed" means at a seeded lane on the ship's row. One boss holds the last phase:
--   Hacker: a rotating spiral of curving streams that reverses now and then.
--   Naysayer: slow walls of bubbles packed tighter than the hitbox, each with one gap at a random x.
--   Swarm: rings of shots; at half HP it splits into 3 children. The children are generated with the schedule,
--   dormant (ActiveFrom = nil, their bullets don't fly) until the split, which the server tells the client (SplitAt).
-- Schedule decisions use only times and RNG draws, never sin/cos results, so client and server build the same list.
--
-- Kills (Kill): Act 2's claim model. One claim takes one HP from a live, on-screen enemy; each weapon can claim at
-- most floor(elapsed / Interval) × PerShot + ShotBudgetSlack kills, and a wingman's weapon needs its role hired.
-- Once every boss is down (BossDownAt), judging stops there and the battle ships.

export type BossKind = "Hacker" | "Naysayer" | "Swarm"
export type Weapon = "Ship" | "Spread" | "Beam" | "Missile"
-- Act 2 wingman weapons (GameConfig.SQUAD.Weapons); declared here because pure modules cannot require GameConfig.
export type WeaponRules = { Role: string, Interval: number, PerShot: number }
export type Loadout = { Shield: boolean, ExtraLife: boolean, Homing: boolean, FireInterval: number }
export type Options = { Boss: BossKind, EliteHalfWaves: number, Loadout: Loadout, Wingmen: { string } }

export type Config = {
	ShipSpeed: number,
	ShipSlack: number,
	ShipMinY: number,
	ShipMaxY: number,
	HitRadius: number,
	GrazeRadius: number,
	Lives: number,
	InvulnSeconds: number,
	LatencyGrace: number,
	Duration: number,
	WaveCount: number,
	WaveSeconds: number,
	BossSeconds: number,
	BulletSpeed: number,
	EliteWaveSeconds: number,
	BossHp: number,
	SwarmChildHp: number,
	VisibleDelay: number,
	ShotBudgetSlack: number,
	Weapons: { Spread: WeaponRules, Beam: WeaponRules, Missile: WeaponRules },
}

-- Fired from (X, Y) at velocity (VX, VY); Curve (radians/s) turns the velocity for the first CURVE_SECONDS.
-- Owner: the id of the enemy that fired it, 0 for none.
export type Bullet = {
	Id: number,
	FiredAt: number,
	X: number,
	Y: number,
	VX: number,
	VY: number,
	Curve: number,
	GoneAt: number,
	Owner: number,
}

export type EnemyKind = "Popcorn" | "Boss" | "Child"
export type Enemy = {
	Id: number,
	Kind: EnemyKind,
	SpawnAt: number, -- a child shares its boss's: it orbits the boss's path
	LeaveAt: number,
	X: number, -- where it hovers; the boss sways around it
	Y: number,
	Phase: number, -- sway phase (popcorn) or orbit angle (child), radians
	Hp: number,
	ActiveFrom: number?, -- nil while a Swarm child is dormant
	KilledAt: number?,
}

export type PhaseKind = "Wave" | "Elite" | "Boss"
export type Phase = { Kind: PhaseKind, StartsAt: number, EndsAt: number }

-- D: total distance the ship was allowed to fly from battle start to T (slack not included).
export type ShipSample = { T: number, X: number, Y: number, D: number }
export type BattleStatus = "Running" | "Shipped" | "Failed"

export type Battle = {
	StartTime: number,
	EndsAt: number,
	Options: Options,
	Config: Config,
	Phases: { Phase }, -- in time order; each is a "wave" for the shield
	Bullets: { Bullet }, -- sorted by FiredAt, Id = index
	Enemies: { Enemy }, -- Id = index: popcorn in spawn order, then the boss, then its children
	Killed: number,
	WeaponShots: { [string]: number }, -- kills claimed per Weapon
	SplitAt: number?, -- when the Swarm split and its children became active
	BossDownAt: number?,
	Lives: number,
	MaxLives: number,
	InvulnUntil: number,
	ShieldUsedPhase: number, -- index of the phase whose shield is spent, 0 if none
	Grazes: number,
	Combo: number,
	MaxCombo: number,
	Grazed: { [number]: boolean }, -- bullet ids already grazed
	Spent: { [number]: boolean }, -- bullet ids that hit (absorbed by the shield or cost a life)
	ShipSamples: { ShipSample }, -- the last 2 s of ship positions plus one older anchor, oldest first
	JudgedStep: number, -- grid steps 1..JudgedStep (StartTime + step/30) are judged
	BulletCursor: number, -- bullets before this index are gone or spent
	Status: BattleStatus,
}

export type BattleResult = { Status: BattleStatus, Score: number, Grazes: number, MaxCombo: number, LivesLeft: number }

local STEPS_PER_SECOND = 30
local STEP = 1 / STEPS_PER_SECOND
local FIELD_MIN = -0.1
local FIELD_MAX = 1.1
local CURVE_SECONDS = 2
local MAX_LIFETIME = 15 -- a bullet slow enough to linger is gone after this anyway
local SHIP_MIN_X = 0.04
local SHIP_MAX_X = 0.96
local SHIP_START_X = 0.5
local SHIP_START_Y = 0.85
local SHIP_HISTORY = 2
local SHIP_MIN_GAP = 0.05 -- a sample this close to the one before the last replaces the last, so bursts can't grow the list
local RNG_WARMUP = 8 -- xorshift's first draws barely differ for nearby seeds
local TAU = 2 * math.pi
local OFF_TOP_Y = -0.1 -- enemies fly in from and out to here
local LANE_Y = 0.9 -- aimed fans aim at a seeded x on this row
-- Popcorn: groups every Gap seconds of Size enemies STAGGER apart; each fires a volley every Volley seconds while it
-- hovers: a Fan-wide fan at a lane or a STREAM_SHOTS straight stream. Index 1, 2 = first, later waves; 3 = elite.
local LEVELS = {
	{ Gap = 2.6, Size = 3, Volley = 1.1, Fan = 3 },
	{ Gap = 2.1, Size = 3, Volley = 0.95, Fan = 3 },
	{ Gap = 1.7, Size = 4, Volley = 0.85, Fan = 5 },
}
local POPCORN_STAGGER = 0.15
local POPCORN_ENTRY = 1
local POPCORN_HOVER = 4 -- seconds from spawn to leaving
local POPCORN_EXIT = 0.8
local POPCORN_SWAY = 0.03
local POPCORN_SPACING = 0.12
local FAN_SPREAD = 0.5 -- radians across a fan
local STREAM_SHOTS = 3
local STREAM_GAP = 0.1
local BOSS_X, BOSS_Y = 0.5, 0.2
local BOSS_ENTRY = 2
local BOSS_SWAY = 0.22
local HACKER_ARMS = 5
local HACKER_INTERVAL = 0.14
local HACKER_SPIN = 0.7 -- radians/s the spiral turns
local HACKER_CURVE = 0.35 -- radians/s each stream bends, the same way as the spin
local HACKER_FLIP_SHOTS = 43 -- the spin reverses every ~6 s
local HACKER_PAUSE_SHOTS = 5 -- ~0.7 s without shots at each reversal
local HACKER_SPEED = 0.85 -- × BulletSpeed
local NAYSAYER_ROW_GAP = 1.4
local NAYSAYER_SPACING = 0.022 -- under 2 × HitRadius: only the gap gets through
local NAYSAYER_BUBBLES = 45 -- across x 0.01-0.978
local NAYSAYER_GAP = 0.18
local NAYSAYER_SPEED = 0.6 -- × BulletSpeed
local SWARM_RING = 16
local SWARM_RING_GAP = 1.1
local SWARM_RING_SPEED = 0.8 -- × BulletSpeed
local CHILD_ORBIT_X, CHILD_ORBIT_Y = 0.2, 0.1
local CHILD_VOLLEY = 1.2
local CHILD_FAN = 5

local BulletHell = {}

-- xorshift32: the same seed gives the same sequence everywhere (bit32 is plain Luau).
function BulletHell.Rng(seed: number): () -> number
	local state = bit32.bxor(math.floor(seed) % 4294967296, 0x9E3779B9)
	if state == 0 then
		state = 0x9E3779B9
	end
	local function nextValue(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
	for _ = 1, RNG_WARMUP do
		nextValue()
	end
	return nextValue
end

-- Where a bullet is at time t. Shared by server and client.
function BulletHell.BulletPosition(bullet: Bullet, t: number): (number, number)
	local dt = math.max(t - bullet.FiredAt, 0)
	local w = bullet.Curve
	if w == 0 then
		return bullet.X + bullet.VX * dt, bullet.Y + bullet.VY * dt
	end
	-- velocity rotates at w while turning: integrate (VX cos wt - VY sin wt, VX sin wt + VY cos wt), then fly straight
	local turn = math.min(dt, CURVE_SECONDS)
	local s, c = math.sin(w * turn), math.cos(w * turn)
	local x = bullet.X + (bullet.VX * s + bullet.VY * (c - 1)) / w
	local y = bullet.Y + (bullet.VX * (1 - c) + bullet.VY * s) / w
	local rest = dt - turn
	return x + (bullet.VX * c - bullet.VY * s) * rest, y + (bullet.VX * s + bullet.VY * c) * rest
end

local function outside(x: number, y: number): boolean
	return x < FIELD_MIN or x > FIELD_MAX or y < FIELD_MIN or y > FIELD_MAX
end

-- Seconds until a point flying straight at (vx, vy) crosses the field's far edge.
local function straightExit(x: number, y: number, vx: number, vy: number): number
	local exit = math.huge
	if vx > 0 then
		exit = math.min(exit, (FIELD_MAX - x) / vx)
	elseif vx < 0 then
		exit = math.min(exit, (FIELD_MIN - x) / vx)
	end
	if vy > 0 then
		exit = math.min(exit, (FIELD_MAX - y) / vy)
	elseif vy < 0 then
		exit = math.min(exit, (FIELD_MIN - y) / vy)
	end
	return math.max(exit, 0)
end

local function lifetime(bullet: Bullet): number
	local w = bullet.Curve
	if w == 0 then
		return straightExit(bullet.X, bullet.Y, bullet.VX, bullet.VY)
	end
	-- while turning, march the grid; a curved bullet must start inside the field
	for step = 1, math.ceil(CURVE_SECONDS * STEPS_PER_SECOND) do
		local dt = math.min(step / STEPS_PER_SECOND, CURVE_SECONDS)
		if outside(BulletHell.BulletPosition(bullet, bullet.FiredAt + dt)) then
			return dt
		end
	end
	local x, y = BulletHell.BulletPosition(bullet, bullet.FiredAt + CURVE_SECONDS)
	local s, c = math.sin(w * CURVE_SECONDS), math.cos(w * CURVE_SECONDS)
	return CURVE_SECONDS + straightExit(x, y, bullet.VX * c - bullet.VY * s, bullet.VX * s + bullet.VY * c)
end

-- A bullet with its GoneAt worked out. Emitters and tests build bullets through this.
function BulletHell.NewBullet(
	id: number,
	firedAt: number,
	x: number,
	y: number,
	vx: number,
	vy: number,
	curve: number,
	owner: number?
): Bullet
	local bullet: Bullet =
		{ Id = id, FiredAt = firedAt, X = x, Y = y, VX = vx, VY = vy, Curve = curve, GoneAt = firedAt, Owner = owner or 0 }
	bullet.GoneAt = firedAt + math.min(lifetime(bullet), MAX_LIFETIME)
	return bullet
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 2
end

-- The boss's path; a child orbits it.
local function bossCentre(enemy: Enemy, t: number): (number, number)
	local dt = math.max(t - enemy.SpawnAt, 0)
	return enemy.X + BOSS_SWAY * math.sin(0.5 * dt), OFF_TOP_Y + (enemy.Y - OFF_TOP_Y) * easeOut(math.min(dt / BOSS_ENTRY, 1))
end

-- Where an enemy is at time t. Shared by server and client.
function BulletHell.EnemyPosition(enemy: Enemy, t: number): (number, number)
	if enemy.Kind == "Popcorn" then
		local dt = math.max(t - enemy.SpawnAt, 0)
		local x = enemy.X + POPCORN_SWAY * math.sin(1.6 * dt + enemy.Phase)
		if t > enemy.LeaveAt then
			return x, enemy.Y + (OFF_TOP_Y - enemy.Y) * math.min((t - enemy.LeaveAt) / POPCORN_EXIT, 1)
		end
		return x, OFF_TOP_Y + (enemy.Y - OFF_TOP_Y) * easeOut(math.min(dt / POPCORN_ENTRY, 1))
	end
	local x, y = bossCentre(enemy, t)
	if enemy.Kind == "Child" then
		local angle = enemy.Phase + 0.9 * (t - enemy.SpawnAt)
		return x + CHILD_ORBIT_X * math.cos(angle), y + CHILD_ORBIT_Y * math.sin(angle)
	end
	return x, y
end

-- Whether a scheduled bullet flies: its owner was active and alive when it fired. The client mirrors ActiveFrom and
-- KilledAt from the server, so it hides the same bullets the server stops judging.
function BulletHell.Fired(b: Battle, bullet: Bullet): boolean
	local owner = b.Enemies[bullet.Owner]
	if not owner then
		return true
	end
	local activeFrom, killedAt = owner.ActiveFrom, owner.KilledAt
	return activeFrom ~= nil and bullet.FiredAt >= activeFrom and (killedAt == nil or bullet.FiredAt <= killedAt)
end

type Fire = (owner: number, firedAt: number, x: number, y: number, vx: number, vy: number, curve: number) -> ()
type AddEnemy = (kind: EnemyKind, spawnAt: number, leaveAt: number, x: number, y: number, phase: number, hp: number) -> Enemy

-- count (>= 2) bullets spread evenly across FAN_SPREAD around `angle` (radians off straight down).
local function fan(fire: Fire, owner: number, t: number, x: number, y: number, angle: number, count: number, speed: number)
	for i = 1, count do
		local a = angle + FAN_SPREAD * ((i - 1) / (count - 1) - 0.5)
		fire(owner, t, x, y, math.sin(a) * speed, math.cos(a) * speed, 0)
	end
end

local function ring(fire: Fire, owner: number, t: number, x: number, y: number, offset: number, count: number, speed: number)
	for i = 0, count - 1 do
		local a = offset + i * TAU / count
		fire(owner, t, x, y, math.sin(a) * speed, math.cos(a) * speed, 0)
	end
end

-- Groups of popcorn enter in a row, hover, fire, and fly back up before the phase ends.
local function emitWave(phase: Phase, level: number, cfg: Config, rng: () -> number, addEnemy: AddEnemy, fire: Fire)
	local rules = LEVELS[level]
	local speed = cfg.BulletSpeed
	local t = phase.StartsAt + 0.5
	while t + (rules.Size - 1) * POPCORN_STAGGER + POPCORN_ENTRY + 1 < phase.EndsAt do
		local centre = 0.2 + rng() * 0.6
		local y = 0.1 + rng() * 0.18
		local aimed = rng() < 0.5
		for i = 1, rules.Size do
			local spawnAt = t + (i - 1) * POPCORN_STAGGER
			local x = math.clamp(centre + (i - (rules.Size + 1) / 2) * POPCORN_SPACING, 0.06, 0.94)
			local enemy = addEnemy("Popcorn", spawnAt, math.min(spawnAt + POPCORN_HOVER, phase.EndsAt), x, y, rng() * TAU, 1)
			local laneX = 0.15 + rng() * 0.7
			local volley = 0
			local fireAt = spawnAt + POPCORN_ENTRY + 0.2
			while fireAt + STREAM_SHOTS * STREAM_GAP < enemy.LeaveAt do
				if aimed then
					local ex, ey = BulletHell.EnemyPosition(enemy, fireAt)
					fan(fire, enemy.Id, fireAt, ex, ey, math.atan2(laneX - ex, LANE_Y - ey), rules.Fan, speed)
				else
					for k = 0, STREAM_SHOTS - 1 do
						local at = fireAt + k * STREAM_GAP
						local ex, ey = BulletHell.EnemyPosition(enemy, at)
						fire(enemy.Id, at, ex, ey, 0, speed, 0)
					end
				end
				volley += 1
				fireAt = spawnAt + POPCORN_ENTRY + 0.2 + volley * rules.Volley
			end
		end
		t += rules.Gap
	end
end

local function emitBoss(phase: Phase, boss: BossKind, cfg: Config, rng: () -> number, addEnemy: AddEnemy, fire: Fire)
	local enemy = addEnemy("Boss", phase.StartsAt, phase.EndsAt, BOSS_X, BOSS_Y, 0, cfg.BossHp)
	local firstShot = phase.StartsAt + BOSS_ENTRY
	local speed = cfg.BulletSpeed
	local shot = 0
	local t = firstShot
	if boss == "Hacker" then
		local angle, spin = 0, 1
		while t < phase.EndsAt do
			local x, y = BulletHell.EnemyPosition(enemy, t)
			for arm = 0, HACKER_ARMS - 1 do
				local a = angle + arm * TAU / HACKER_ARMS
				fire(enemy.Id, t, x, y, math.sin(a) * speed * HACKER_SPEED, math.cos(a) * speed * HACKER_SPEED, HACKER_CURVE * spin)
			end
			shot += 1
			if shot % (HACKER_FLIP_SHOTS + HACKER_PAUSE_SHOTS) == HACKER_FLIP_SHOTS then
				spin = -spin -- pause, then reverse: old and new streams don't cross into a closed pocket
				shot += HACKER_PAUSE_SHOTS
			end
			angle += HACKER_SPIN * HACKER_INTERVAL * spin
			t = firstShot + shot * HACKER_INTERVAL
		end
	elseif boss == "Naysayer" then
		-- bubbles rain from the top edge in walls; the gap is centred at gapX
		while t < phase.EndsAt do
			local gapX = 0.15 + rng() * 0.7
			for i = 0, NAYSAYER_BUBBLES - 1 do
				local x = 0.01 + i * NAYSAYER_SPACING
				if math.abs(x - gapX) > NAYSAYER_GAP / 2 then
					fire(enemy.Id, t, x, 0.02, 0, speed * NAYSAYER_SPEED, 0)
				end
			end
			shot += 1
			t = firstShot + shot * NAYSAYER_ROW_GAP
		end
	else
		local children: { Enemy } = {}
		for k = 1, 3 do
			local child = addEnemy("Child", phase.StartsAt, phase.EndsAt, BOSS_X, BOSS_Y, (k - 1) * TAU / 3, cfg.SwarmChildHp)
			child.ActiveFrom = nil -- dormant until the split
			table.insert(children, child)
		end
		while t < phase.EndsAt do
			local x, y = BulletHell.EnemyPosition(enemy, t)
			ring(fire, enemy.Id, t, x, y, rng() * TAU, SWARM_RING, speed * SWARM_RING_SPEED)
			shot += 1
			t = firstShot + shot * SWARM_RING_GAP
		end
		-- the children's fans, staggered; they only fly after the split
		for k, child in children do
			local volley = 0
			local fireAt = firstShot + (k - 1) * CHILD_VOLLEY / 3
			while fireAt < phase.EndsAt do
				local x, y = BulletHell.EnemyPosition(child, fireAt)
				fan(fire, child.Id, fireAt, x, y, math.atan2(0.15 + rng() * 0.7 - x, LANE_Y - y), CHILD_FAN, speed)
				volley += 1
				fireAt = firstShot + (k - 1) * CHILD_VOLLEY / 3 + volley * CHILD_VOLLEY
			end
		end
	end
end

function BulletHell.New(start: number, seed: number, options: Options, cfg: Config): Battle
	local phases: { Phase } = {}
	local clock = start
	local function addPhase(kind: PhaseKind, seconds: number)
		table.insert(phases, { Kind = kind, StartsAt = clock, EndsAt = clock + seconds })
		clock += seconds
	end
	for _ = 1, cfg.WaveCount do
		addPhase("Wave", cfg.WaveSeconds)
	end
	local eliteSeconds = cfg.EliteWaveSeconds * math.max(options.EliteHalfWaves, 0) / 2
	if eliteSeconds > 0 then
		addPhase("Elite", eliteSeconds)
	end
	addPhase("Boss", cfg.BossSeconds)

	type Shot = { FiredAt: number, X: number, Y: number, VX: number, VY: number, Curve: number, Owner: number, Order: number }
	local shots: { Shot } = {}
	local enemies: { Enemy } = {}
	local rng = BulletHell.Rng(seed)
	local function fire(owner: number, firedAt: number, x: number, y: number, vx: number, vy: number, curve: number)
		table.insert(
			shots,
			{ FiredAt = firedAt, X = x, Y = y, VX = vx, VY = vy, Curve = curve, Owner = owner, Order = #shots + 1 }
		)
	end
	local function addEnemy(kind: EnemyKind, spawnAt: number, leaveAt: number, x: number, y: number, phase: number, hp: number): Enemy
		local enemy: Enemy = {
			Id = #enemies + 1,
			Kind = kind,
			SpawnAt = spawnAt,
			LeaveAt = leaveAt,
			X = x,
			Y = y,
			Phase = phase,
			Hp = hp,
			ActiveFrom = spawnAt,
			KilledAt = nil,
		}
		table.insert(enemies, enemy)
		return enemy
	end
	for index, phase in phases do
		if phase.Kind == "Boss" then
			emitBoss(phase, options.Boss, cfg, rng, addEnemy, fire)
		else
			emitWave(phase, if phase.Kind == "Elite" then 3 else math.min(index, 2), cfg, rng, addEnemy, fire)
		end
	end
	table.sort(shots, function(a: Shot, b: Shot): boolean
		if a.FiredAt ~= b.FiredAt then
			return a.FiredAt < b.FiredAt
		end
		return a.Order < b.Order -- table.sort isn't stable; keep emission order so ids match on both sides
	end)
	local bullets: { Bullet } = {}
	for i, shot in shots do
		bullets[i] = BulletHell.NewBullet(i, shot.FiredAt, shot.X, shot.Y, shot.VX, shot.VY, shot.Curve, shot.Owner)
	end

	local lives = cfg.Lives + (if options.Loadout.ExtraLife then 1 else 0)
	return {
		StartTime = start,
		EndsAt = clock,
		Options = options,
		Config = cfg,
		Phases = phases,
		Bullets = bullets,
		Enemies = enemies,
		Killed = 0,
		WeaponShots = {},
		SplitAt = nil,
		BossDownAt = nil,
		Lives = lives,
		MaxLives = lives,
		InvulnUntil = start,
		ShieldUsedPhase = 0,
		Grazes = 0,
		Combo = 0,
		MaxCombo = 0,
		Grazed = {},
		Spent = {},
		ShipSamples = { { T = start, X = SHIP_START_X, Y = SHIP_START_Y, D = 0 } },
		JudgedStep = 0,
		BulletCursor = 1,
		Status = "Running",
	}
end

-- The client streams its ship position; the server's clock is `now`. See the header for the clamp.
function BulletHell.MoveShip(b: Battle, x: number, y: number, now: number)
	local samples = b.ShipSamples
	local last = samples[#samples]
	if x ~= x or y ~= y or now ~= now or now < last.T then
		return
	end
	local cfg = b.Config
	local travel = last.D + cfg.ShipSpeed * (now - last.T)
	local dx = math.clamp(x, SHIP_MIN_X, SHIP_MAX_X) - last.X
	local dy = math.clamp(y, cfg.ShipMinY, cfg.ShipMaxY) - last.Y
	local dd = dx * dx + dy * dy
	local reach = 1
	if dd > 0 then
		for _, sample in samples do
			-- largest s in [0, 1] with |last + s·d - sample| <= r; s = 0 always fits (last lies in every disc)
			local r = travel - sample.D + cfg.ShipSlack
			local ax, ay = last.X - sample.X, last.Y - sample.Y
			local ad = ax * dx + ay * dy
			local discriminant = ad * ad - dd * (ax * ax + ay * ay - r * r)
			reach = math.min(reach, (-ad + math.sqrt(math.max(discriminant, 0))) / dd)
		end
		reach = math.max(reach, 0)
	end
	local sample = { T = now, X = last.X + reach * dx, Y = last.Y + reach * dy, D = travel }
	local previous = samples[#samples - 1]
	if previous and now - previous.T < SHIP_MIN_GAP then
		samples[#samples] = sample -- keep the older anchor, replace the in-between one
	else
		table.insert(samples, sample)
	end
	-- keep the newest sample older than the window as an anchor. Samples two apart are >= SHIP_MIN_GAP apart, so the
	-- list stays bounded: at most 2 * SHIP_HISTORY / SHIP_MIN_GAP + 1 in the window, plus the anchor (82)
	while #samples >= 2 and samples[2].T < now - SHIP_HISTORY do
		table.remove(samples, 1)
	end
end

-- Where the ship was at time t, interpolated between samples (clients draw it moving smoothly, not jumping).
function BulletHell.ShipAt(b: Battle, t: number): (number, number)
	local samples = b.ShipSamples
	local previous = samples[1]
	if t <= previous.T then
		return previous.X, previous.Y
	end
	for i = 2, #samples do
		local sample = samples[i]
		if sample.T >= t then
			local f = (t - previous.T) / (sample.T - previous.T)
			return previous.X + (sample.X - previous.X) * f, previous.Y + (sample.Y - previous.Y) * f
		end
		previous = sample
	end
	return previous.X, previous.Y
end

local function phaseAt(b: Battle, t: number): number
	local index = 1
	for i, phase in b.Phases do
		if phase.StartsAt <= t then
			index = i
		end
	end
	return index
end

local function hit(b: Battle, bullet: Bullet, t: number)
	b.Spent[bullet.Id] = true
	local phase = phaseAt(b, t)
	if b.Options.Loadout.Shield and b.ShieldUsedPhase ~= phase then
		b.ShieldUsedPhase = phase -- the shield keeps the combo alive
		return
	end
	b.Lives -= 1
	b.Combo = 0
	b.InvulnUntil = t + b.Config.InvulnSeconds
	if b.Lives <= 0 then
		b.Status = "Failed"
	end
end

local live: { Bullet } = {} -- scratch for Tick, reused (Tick never yields or recurses)

-- Judges every grid step up to now - LatencyGrace (and no further than the end or the boss going down), then
-- settles the status.
function BulletHell.Tick(b: Battle, now: number)
	if b.Status ~= "Running" or now ~= now then
		return
	end
	local cfg = b.Config
	local endStep = math.floor((b.EndsAt - b.StartTime) * STEPS_PER_SECOND + 0.5)
	local bossDownAt = b.BossDownAt
	if bossDownAt then
		endStep = math.min(endStep, math.ceil((bossDownAt - b.StartTime) * STEPS_PER_SECOND))
	end
	local lastStep = math.min(math.floor((now - cfg.LatencyGrace - b.StartTime) * STEPS_PER_SECOND), endStep)
	local fromT = b.StartTime + (b.JudgedStep + 1) / STEPS_PER_SECOND
	local toT = b.StartTime + lastStep / STEPS_PER_SECOND

	-- only bullets alive somewhere in [fromT - STEP, toT] (the first substep sweeps back from fromT)
	local bullets = b.Bullets
	local firstT = fromT - STEP
	while bullets[b.BulletCursor] and (bullets[b.BulletCursor].GoneAt < firstT or b.Spent[bullets[b.BulletCursor].Id]) do
		b.BulletCursor += 1
	end
	table.clear(live)
	for i = b.BulletCursor, #bullets do
		local bullet = bullets[i]
		if bullet.FiredAt > toT then
			break
		end
		if bullet.GoneAt >= firstT and not b.Spent[bullet.Id] and BulletHell.Fired(b, bullet) then
			table.insert(live, bullet)
		end
	end

	local hitSquared, grazeSquared = cfg.HitRadius ^ 2, cfg.GrazeRadius ^ 2
	for step = b.JudgedStep + 1, lastStep do
		b.JudgedStep = step
		local t = b.StartTime + step / STEPS_PER_SECOND
		if t < b.InvulnUntil or #live == 0 then
			continue -- no hits and no grazes while invulnerable, so a hit can't be farmed for grazes
		end
		local shipStartX, shipStartY = BulletHell.ShipAt(b, t - STEP)
		local shipEndX, shipEndY = BulletHell.ShipAt(b, t)
		for _, bullet in live do
			if bullet.FiredAt > t or bullet.GoneAt < t - STEP or b.Spent[bullet.Id] or t < b.InvulnUntil then
				continue
			end
			-- sweep [t0, t]: closest approach of the bullet relative to the ship, both moving linearly across it
			local t0, sx0, sy0 = t - STEP, shipStartX, shipStartY
			if bullet.FiredAt > t0 then
				t0 = bullet.FiredAt -- fired mid-substep: start from its muzzle, not before it existed
				sx0, sy0 = BulletHell.ShipAt(b, t0)
			end
			local x0, y0 = BulletHell.BulletPosition(bullet, t0)
			local x1, y1 = BulletHell.BulletPosition(bullet, t)
			local rx, ry = x0 - sx0, y0 - sy0
			local dx, dy = (x1 - shipEndX) - rx, (y1 - shipEndY) - ry
			local dd = dx * dx + dy * dy
			local u = if dd > 0 then math.clamp(-(rx * dx + ry * dy) / dd, 0, 1) else 0
			local distanceSquared = (rx + u * dx) ^ 2 + (ry + u * dy) ^ 2
			if distanceSquared <= hitSquared then
				hit(b, bullet, t)
				if b.Status ~= "Running" then
					return
				end
			elseif distanceSquared <= grazeSquared and not b.Grazed[bullet.Id] then
				b.Grazed[bullet.Id] = true
				b.Grazes += 1
				b.Combo += 1
				b.MaxCombo = math.max(b.MaxCombo, b.Combo)
			end
		end
	end
	if b.JudgedStep >= endStep then
		b.Status = "Shipped" -- time up or boss down, with lives left
	end
end

-- Fire interval and kills per volley for a weapon, or nil if the battle doesn't have it (a wingman needs its hire).
local function weaponRate(b: Battle, weapon: Weapon): (number?, number)
	if weapon == "Ship" then
		return b.Options.Loadout.FireInterval, 1
	end
	local weapons = b.Config.Weapons
	local rules = if weapon == "Spread"
		then weapons.Spread
		elseif weapon == "Beam" then weapons.Beam
		elseif weapon == "Missile" then weapons.Missile
		else nil
	if not rules or not table.find(b.Options.Wingmen, rules.Role) then
		return nil, 0
	end
	return rules.Interval, rules.PerShot
end

local function bossesDown(b: Battle): boolean
	for _, enemy in b.Enemies do
		if enemy.Kind ~= "Popcorn" and not enemy.KilledAt then
			return false
		end
	end
	return true
end

-- A shot hit an enemy (the client reports its id and the weapon, Ship by default). Valid only if the enemy is active,
-- alive and on screen, and that weapon can't have fired more shots than its rate allows. One claim takes one HP.
function BulletHell.Kill(b: Battle, enemyId: number, now: number, weapon: Weapon?): boolean
	BulletHell.Tick(b, now)
	local enemy = b.Enemies[enemyId]
	if b.Status ~= "Running" or now ~= now or not enemy or enemy.KilledAt then
		return false
	end
	local cfg = b.Config
	local activeFrom = enemy.ActiveFrom
	if not activeFrom or now < activeFrom + cfg.VisibleDelay or now > enemy.LeaveAt + cfg.LatencyGrace then
		return false
	end
	local chosen: Weapon = weapon or "Ship"
	local interval, perShot = weaponRate(b, chosen)
	if not interval then
		return false
	end
	local used = b.WeaponShots[chosen] or 0
	if used >= math.floor((now - b.StartTime) / interval) * perShot + cfg.ShotBudgetSlack then
		return false
	end

	b.WeaponShots[chosen] = used + 1
	b.Combo += 1
	b.MaxCombo = math.max(b.MaxCombo, b.Combo)
	enemy.Hp -= 1
	if enemy.Kind == "Boss" and b.Options.Boss == "Swarm" and enemy.Hp <= cfg.BossHp / 2 then
		enemy.Hp = 0 -- the Swarm splits: its dormant children spawn around where it is
		b.SplitAt = now
		for _, child in b.Enemies do
			if child.Kind == "Child" then
				child.ActiveFrom = now
			end
		end
	end
	if enemy.Hp <= 0 then
		enemy.KilledAt = now
		b.Killed += 1
		if enemy.Kind ~= "Popcorn" and bossesDown(b) then
			b.BossDownAt = now
		end
	end
	return true
end

-- In [0, 2]; feeds Economy.Payout as the battle score.
function BulletHell.Score(b: Battle): number
	local accuracy = b.Killed / math.max(#b.Enemies, 1)
	return math.clamp(
		0.6 * accuracy
			+ 0.4 * math.min(b.Grazes / 40, 1)
			+ 0.5 * math.min(b.MaxCombo / 30, 1)
			+ 0.5 * math.max(b.Lives, 0) / b.MaxLives,
		0,
		2
	)
end

function BulletHell.Result(b: Battle): BattleResult
	return {
		Status = b.Status,
		Score = BulletHell.Score(b),
		Grazes = b.Grazes,
		MaxCombo = b.MaxCombo,
		LivesLeft = math.max(b.Lives, 0),
	}
end

return BulletHell
