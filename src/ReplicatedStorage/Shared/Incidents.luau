--!strict
-- Act 3 incident rules: pure scheduling and consequences. No requires, no Roblox APIs: the caller passes in
--   cfg      GameConfig.INCIDENTS
--   stations GameConfig.COMPONENTS (the order a Breach picks its locked station from)
--   rng      () -> number in [0, 1), e.g. Random.new():NextNumber
--   keyHires { [KeyHireId]: boolean }, ids from GameConfig.KEY_HIRES ("SecurityEngineer", "QAManager", "PRLead")
-- The server calls Tick every ~0.5 s and applies the returned events. Times are in seconds on any shared clock.

export type Kind = "Breach" | "Vulnerability" | "Naysayer"
export type Incident = { Kind: Kind, StartedAt: number, Deadline: number, LockedStation: string? }
export type Config = {
	MinGap: number,
	MaxGap: number,
	FreePlayMinGap: number,
	FreePlayMaxGap: number,
	RespondSeconds: number,
	LockSeconds: number,
	IgnorePenalty: number,
	GoodBonus: number,
	DrainEvery: number,
	DrainSeconds: number,
	AutoClearSeconds: number,
}
-- Locks maps a station to its unlock time. EliteWaves counts pending half-waves (2 = one full wave).
-- NextDrainAt is the next reputation drain while now <= DrainUntil.
export type State = {
	Active: Incident?,
	NextAt: number,
	Locks: { [string]: number },
	DrainUntil: number,
	NextDrainAt: number,
	EliteWaves: number,
}
export type Event = {
	Type: "Start" | "AutoCleared" | "Ignored" | "Drain",
	Incident: Incident?,
	Kind: Kind?,
	RepDelta: number?,
}

local KINDS: { Kind } = { "Breach", "Vulnerability", "Naysayer" }

local Incidents = {}

local function rollIndex(count: number, rng: () -> number): number
	return math.min(count, math.floor(rng() * count) + 1)
end

local function gap(cfg: Config, rng: () -> number, freePlay: boolean): number
	local low = if freePlay then cfg.FreePlayMinGap else cfg.MinGap
	local high = if freePlay then cfg.FreePlayMaxGap else cfg.MaxGap
	return low + rng() * (high - low)
end

function Incidents.New(now: number, rng: () -> number, freePlay: boolean, cfg: Config): State
	return { Active = nil, NextAt = now + gap(cfg, rng, freePlay), Locks = {}, DrainUntil = 0, NextDrainAt = math.huge, EliteWaves = 0 }
end

function Incidents.Tick(
	s: State,
	now: number,
	busy: boolean,
	rng: () -> number,
	freePlay: boolean,
	keyHires: { [string]: boolean },
	cfg: Config,
	stations: { string }
): { Event }
	local events: { Event } = {}
	local drainEvery = cfg.DrainEvery * (if keyHires.PRLead then 2 else 1)

	local active = s.Active
	if active then
		if active.Kind == "Breach" and keyHires.SecurityEngineer and now >= active.StartedAt + cfg.AutoClearSeconds then
			s.Active = nil
			s.NextAt = now + gap(cfg, rng, freePlay)
			table.insert(events, { Type = "AutoCleared" })
		elseif now >= active.Deadline then
			local repDelta = -cfg.IgnorePenalty
			if active.Kind == "Breach" then
				local station = active.LockedStation
				if station then
					s.Locks[station] = now + cfg.LockSeconds
				end
			elseif active.Kind == "Vulnerability" then
				s.EliteWaves += if keyHires.QAManager then 1 else 2
			else
				repDelta = 0
				s.DrainUntil = now + cfg.DrainSeconds
				s.NextDrainAt = now + drainEvery
			end
			s.Active = nil
			s.NextAt = now + gap(cfg, rng, freePlay)
			table.insert(events, { Type = "Ignored", Kind = active.Kind, RepDelta = repDelta })
		end
	end

	-- Inclusive of DrainUntil so 60 s at 5 s steps gives 12 drains.
	while now >= s.NextDrainAt and s.NextDrainAt <= s.DrainUntil do
		s.NextDrainAt += drainEvery
		table.insert(events, { Type = "Drain", RepDelta = -1 })
	end

	if not busy and s.Active == nil and now >= s.NextAt then
		local incident: Incident = { Kind = KINDS[rollIndex(#KINDS, rng)], StartedAt = now, Deadline = now + cfg.RespondSeconds }
		if incident.Kind == "Breach" then
			incident.LockedStation = stations[rollIndex(#stations, rng)]
		end
		s.Active = incident
		table.insert(events, { Type = "Start", Incident = incident })
	end

	return events
end

-- Clears the active incident; good grades (S or A) earn reputation. Nothing active means nothing to resolve.
function Incidents.Resolve(s: State, now: number, grade: string, rng: () -> number, freePlay: boolean, cfg: Config): number
	local active = s.Active
	if not active then
		return 0
	end
	s.Active = nil
	s.NextAt = now + gap(cfg, rng, freePlay)
	if active.Kind == "Naysayer" then
		s.DrainUntil = 0
	end
	return if grade == "S" or grade == "A" then cfg.GoodBonus else 0
end

function Incidents.IsLocked(s: State, station: string, now: number): boolean
	local unlockAt = s.Locks[station]
	return unlockAt ~= nil and now < unlockAt
end

-- Consumes the pending waves for the next battle; the battle reads s.EliteWaves first (1 = half wave).
function Incidents.TakeEliteWave(s: State): boolean
	local pending = s.EliteWaves > 0
	s.EliteWaves = 0
	return pending
end

return Incidents
