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
-- Seam for Task 10: emitPhase fills each phase with PLACEHOLDER emitters. Replace its body with the real enemy and
-- boss emitters; they only need to call fire(...) for bullets fired inside the field, in any order.

export type BossKind = "Hacker" | "Naysayer" | "Swarm"
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
}

-- Fired from (X, Y) at velocity (VX, VY); Curve (radians/s) turns the velocity for the first CURVE_SECONDS.
export type Bullet = {
	Id: number,
	FiredAt: number,
	X: number,
	Y: number,
	VX: number,
	VY: number,
	Curve: number,
	GoneAt: number,
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
function BulletHell.NewBullet(id: number, firedAt: number, x: number, y: number, vx: number, vy: number, curve: number): Bullet
	local bullet: Bullet = { Id = id, FiredAt = firedAt, X = x, Y = y, VX = vx, VY = vy, Curve = curve, GoneAt = firedAt }
	bullet.GoneAt = firedAt + math.min(lifetime(bullet), MAX_LIFETIME)
	return bullet
end

type Fire = (firedAt: number, x: number, y: number, vx: number, vy: number, curve: number) -> ()

-- PLACEHOLDER emitters (Task 10 replaces this body with real enemies and boss patterns): fans from the top during
-- waves, denser fans in the elite wave, rings from the boss spot during the boss phase.
local function emitPhase(phase: Phase, cfg: Config, rng: () -> number, fire: Fire)
	local speed = cfg.BulletSpeed
	if phase.Kind == "Boss" then
		local t = phase.StartsAt + 2
		while t < phase.EndsAt do
			local offset = rng() * 2 * math.pi
			for i = 0, 11 do
				local angle = offset + i * math.pi / 6
				fire(t, 0.5, 0.15, math.cos(angle) * speed, math.sin(angle) * speed, 0)
			end
			t += 1.2
		end
		return
	end
	local interval, size = 0.4, 3
	if phase.Kind == "Elite" then
		interval, size = 0.25, 5
	end
	local t = phase.StartsAt + 1
	while t < phase.EndsAt do
		local x = 0.1 + rng() * 0.8
		local aim = (rng() - 0.5) * 0.6
		for i = 1, size do
			local angle = aim + (i - (size + 1) / 2) * 0.3 -- radians off straight down
			fire(t, x, 0.05, math.sin(angle) * speed, math.cos(angle) * speed, 0)
		end
		t += interval
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

	type Shot = { FiredAt: number, X: number, Y: number, VX: number, VY: number, Curve: number, Order: number }
	local shots: { Shot } = {}
	local rng = BulletHell.Rng(seed)
	for _, phase in phases do
		emitPhase(phase, cfg, rng, function(firedAt: number, x: number, y: number, vx: number, vy: number, curve: number)
			table.insert(shots, { FiredAt = firedAt, X = x, Y = y, VX = vx, VY = vy, Curve = curve, Order = #shots + 1 })
		end)
	end
	table.sort(shots, function(a: Shot, b: Shot): boolean
		if a.FiredAt ~= b.FiredAt then
			return a.FiredAt < b.FiredAt
		end
		return a.Order < b.Order -- table.sort isn't stable; keep emission order so ids match on both sides
	end)
	local bullets: { Bullet } = {}
	for i, shot in shots do
		bullets[i] = BulletHell.NewBullet(i, shot.FiredAt, shot.X, shot.Y, shot.VX, shot.VY, shot.Curve)
	end

	local lives = cfg.Lives + (if options.Loadout.ExtraLife then 1 else 0)
	return {
		StartTime = start,
		EndsAt = clock,
		Options = options,
		Config = cfg,
		Phases = phases,
		Bullets = bullets,
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

-- Judges every grid step up to now - LatencyGrace (and no further than the end), then settles the status.
function BulletHell.Tick(b: Battle, now: number)
	if b.Status ~= "Running" or now ~= now then
		return
	end
	local cfg = b.Config
	local endStep = math.floor((b.EndsAt - b.StartTime) * STEPS_PER_SECOND + 0.5)
	local lastStep = math.min(math.floor((now - cfg.LatencyGrace - b.StartTime) * STEPS_PER_SECOND), endStep)
	if lastStep <= b.JudgedStep then
		return
	end
	local fromT = b.StartTime + (b.JudgedStep + 1) / STEPS_PER_SECOND
	local toT = b.StartTime + lastStep / STEPS_PER_SECOND

	-- only bullets alive somewhere in [fromT - STEP, toT] (the first substep sweeps back from fromT)
	local bullets = b.Bullets
	local firstT = fromT - STEP
	while bullets[b.BulletCursor] and (bullets[b.BulletCursor].GoneAt < firstT or b.Spent[bullets[b.BulletCursor].Id]) do
		b.BulletCursor += 1
	end
	local live: { Bullet } = {}
	for i = b.BulletCursor, #bullets do
		local bullet = bullets[i]
		if bullet.FiredAt > toT then
			break
		end
		if bullet.GoneAt >= firstT and not b.Spent[bullet.Id] then
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
		b.Status = "Shipped" -- time up with lives left (Task 10 adds boss down)
	end
end

return BulletHell
