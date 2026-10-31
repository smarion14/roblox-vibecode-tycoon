--!strict
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local Incidents = require("../src/ReplicatedStorage/Shared/Incidents")

local CFG = GameConfig.INCIDENTS
local STATIONS = GameConfig.COMPONENTS
local NONE: { [string]: boolean } = {}
local STEP = 0.5

local function constant(value: number): () -> number
	return function()
		return value
	end
end

-- rng returning the given values in order (Start draws the kind, then the station).
local function sequence(values: { number }): () -> number
	local index = 0
	return function()
		index += 1
		return values[index] or 0
	end
end

local function tick(s: Incidents.State, now: number, busy: boolean, keyHires: { [string]: boolean }?, freePlay: boolean?): { Incidents.Event }
	return Incidents.Tick(s, now, busy, constant(0), freePlay == true, keyHires or NONE, CFG, STATIONS)
end

local function find(events: { Incidents.Event }, eventType: string): Incidents.Event?
	for _, event in events do
		if event.Type == eventType then
			return event
		end
	end
	return nil
end

-- Starts a Breach (kind roll 0) on the first station at its NextAt.
local function startBreach(): (Incidents.State, Incidents.Incident)
	local s = Incidents.New(0, constant(0), false, CFG)
	local events = Incidents.Tick(s, s.NextAt, false, sequence({ 0, 0 }), false, NONE, CFG, STATIONS)
	local start = find(events, "Start")
	assert(start and start.Incident, "expected a Start")
	return s, start.Incident
end

-- Ignores a Naysayer (kind roll 0.99) and returns the state plus the deadline tick time.
local function ignoreNaysayer(keyHires: { [string]: boolean }): (Incidents.State, number)
	local s = Incidents.New(0, constant(0), false, CFG)
	Incidents.Tick(s, s.NextAt, false, sequence({ 0.99 }), false, NONE, CFG, STATIONS)
	local incident = s.Active :: Incidents.Incident
	assert(incident.Kind == "Naysayer")
	local events = tick(s, incident.Deadline, false, keyHires)
	assert(find(events, "Ignored"), "expected Ignored")
	return s, incident.Deadline
end

local tests = {}

tests["first incident waits for the gap"] = function()
	local low = Incidents.New(0, constant(0), false, CFG)
	assert(low.NextAt == 180)
	local high = Incidents.New(0, constant(0.999), false, CFG)
	assert(high.NextAt >= 180 and high.NextAt <= 240)
	local s = Incidents.New(100, constant(0.5), false, CFG)
	assert(s.NextAt >= 280 and s.NextAt <= 340)
	assert(#tick(s, s.NextAt - 1, false) == 0)
	assert(find(tick(s, s.NextAt, false), "Start"))
end

tests["incidents wait while busy"] = function()
	local s = Incidents.New(0, constant(0), false, CFG)
	assert(find(tick(s, s.NextAt + 50, true), "Start") == nil)
	assert(s.Active == nil)
	assert(find(tick(s, s.NextAt + 50, false), "Start"))
end

tests["one incident at a time"] = function()
	local s, incident = startBreach()
	s.NextAt = incident.StartedAt -- force the schedule to be due again
	assert(find(tick(s, incident.StartedAt + 1, false), "Start") == nil)
	assert(s.Active == incident)
end

tests["ignored breach locks a station then expires"] = function()
	local s, incident = startBreach()
	assert(incident.Kind == "Breach")
	local station = incident.LockedStation :: string
	assert(station == STATIONS[1])
	assert(not Incidents.IsLocked(s, station, incident.Deadline - 1), "locks only once ignored")
	local ignored = find(tick(s, incident.Deadline, false), "Ignored")
	assert(ignored and ignored.RepDelta == -5 and ignored.Kind == "Breach")
	assert(s.Active == nil)
	assert(Incidents.IsLocked(s, station, incident.Deadline + 1))
	assert(Incidents.IsLocked(s, station, incident.Deadline + 119))
	assert(not Incidents.IsLocked(s, station, incident.Deadline + 121))
	assert(not Incidents.IsLocked(s, STATIONS[2], incident.Deadline + 1))
	assert(s.NextAt >= incident.Deadline + 180 and s.NextAt <= incident.Deadline + 240)
end

tests["security engineer auto-clears breaches"] = function()
	local s, incident = startBreach()
	local hires = { SecurityEngineer = true }
	assert(find(tick(s, incident.StartedAt + 29.5, false, hires), "AutoCleared") == nil)
	local events = tick(s, incident.StartedAt + 30, false, hires)
	assert(find(events, "AutoCleared"))
	assert(find(events, "Ignored") == nil)
	assert(s.Active == nil)
	assert(not Incidents.IsLocked(s, incident.LockedStation :: string, incident.Deadline + 1))
	assert(find(tick(s, incident.Deadline, false, hires), "Ignored") == nil)
end

tests["security engineer ignores other kinds"] = function()
	local s = Incidents.New(0, constant(0), false, CFG)
	Incidents.Tick(s, s.NextAt, false, sequence({ 0.99 }), false, NONE, CFG, STATIONS)
	local incident = s.Active :: Incidents.Incident
	assert(incident.Kind == "Naysayer" and incident.LockedStation == nil)
	assert(find(tick(s, incident.StartedAt + 30, false, { SecurityEngineer = true }), "AutoCleared") == nil)
	assert(s.Active == incident)
end

local function countDrains(keyHires: { [string]: boolean }): number
	local s, deadline = ignoreNaysayer(keyHires)
	assert(s.DrainUntil == deadline + 60)
	local drains = 0
	local now = deadline + STEP
	while now <= deadline + 70 do
		for _, event in tick(s, now, false, keyHires) do
			if event.Type == "Drain" then
				assert(event.RepDelta == -1)
				drains += 1
			end
		end
		now += STEP
	end
	return drains
end

tests["naysayer drain is halved by the PR lead"] = function()
	assert(countDrains(NONE) == 12)
	assert(countDrains({ PRLead = true }) == 6)
end

tests["vulnerability adds an elite wave, halved by QA"] = function()
	for _, case in { { hires = NONE, waves = 2 }, { hires = { QAManager = true }, waves = 1 } } do
		local s = Incidents.New(0, constant(0), false, CFG)
		Incidents.Tick(s, s.NextAt, false, sequence({ 0.4 }), false, NONE, CFG, STATIONS)
		local incident = s.Active :: Incidents.Incident
		assert(incident.Kind == "Vulnerability")
		assert(s.EliteWaves == 0)
		local ignored = find(tick(s, incident.Deadline, false, case.hires), "Ignored")
		assert(ignored and ignored.RepDelta == -5)
		assert(s.EliteWaves == case.waves)
		assert(Incidents.TakeEliteWave(s))
		assert(s.EliteWaves == 0)
		assert(not Incidents.TakeEliteWave(s))
	end
end

tests["good handling earns reputation"] = function()
	local s, incident = startBreach()
	assert(Incidents.Resolve(s, incident.StartedAt + 10, "A", constant(0), false, CFG) == 3)
	assert(s.Active == nil)
	assert(s.NextAt == incident.StartedAt + 10 + 180)
	assert(Incidents.Resolve(s, 0, "A", constant(0), true, CFG) == 0)
	s, incident = startBreach()
	assert(Incidents.Resolve(s, incident.StartedAt + 10, "S", constant(0), false, CFG) == 3)
	s, incident = startBreach()
	assert(Incidents.Resolve(s, incident.StartedAt + 10, "C", constant(0), false, CFG) == 0)
	assert(Incidents.Resolve(s, incident.StartedAt + 11, "A", constant(0), false, CFG) == 0, "nothing active to resolve")
end

tests["resolving a naysayer early starts no drain"] = function()
	local s = Incidents.New(0, constant(0), false, CFG)
	Incidents.Tick(s, s.NextAt, false, sequence({ 0.99 }), false, NONE, CFG, STATIONS)
	local incident = s.Active :: Incidents.Incident
	Incidents.Resolve(s, incident.StartedAt + 5, "A", constant(0), false, CFG)
	assert(s.DrainUntil == 0)
	for step = 0, 140 do
		local events = tick(s, incident.StartedAt + 5 + step, false)
		assert(find(events, "Drain") == nil and find(events, "Ignored") == nil)
	end
end

tests["free play spaces incidents out"] = function()
	local low = Incidents.New(0, constant(0), true, CFG)
	assert(low.NextAt == 360)
	local high = Incidents.New(0, constant(0.999), true, CFG)
	assert(high.NextAt >= 360 and high.NextAt <= 480)
	local s, incident = startBreach()
	assert(find(Incidents.Tick(s, incident.Deadline, false, constant(0.5), true, NONE, CFG, STATIONS), "Ignored"))
	assert(s.NextAt >= incident.Deadline + 360 and s.NextAt <= incident.Deadline + 480)
end

return tests
