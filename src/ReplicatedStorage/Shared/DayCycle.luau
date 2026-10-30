--!strict
-- Pure: no requires, no Roblox APIs. Every client computes the same time of day from the shared server clock,
-- so the cycle stays in sync without the server sending anything.

export type CycleConfig = {
	DayLengthSeconds: number,
	StartClock: number,
}

local DAWN_START = 5
local DAWN_END = 7
local DUSK_START = 17
local DUSK_END = 19

local DayCycle = {}

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Clock hour (0-24) at a given server time.
function DayCycle.ClockAt(serverTime: number, config: CycleConfig): number
	local progress = (serverTime / config.DayLengthSeconds) % 1
	return (config.StartClock + progress * 24) % 24
end

-- 1 in full day, 0 in full night, eased through dawn (5-7) and dusk (17-19).
function DayCycle.Daylight(clock: number): number
	if clock < DUSK_START then
		return smoothstep(DAWN_START, DAWN_END, clock)
	end
	return 1 - smoothstep(DUSK_START, DUSK_END, clock)
end

function DayCycle.IsNight(clock: number): boolean
	return DayCycle.Daylight(clock) < 0.5
end

return DayCycle
