--!strict
local DayCycle = require("../src/ReplicatedStorage/Shared/DayCycle")

local CONFIG: DayCycle.CycleConfig = { DayLengthSeconds = 600, StartClock = 9 }

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

local tests = {}

tests["clock starts at the configured hour"] = function()
	assert(near(DayCycle.ClockAt(0, CONFIG), 9))
end

tests["clock advances a full day per cycle and wraps"] = function()
	assert(near(DayCycle.ClockAt(150, CONFIG), 15)) -- a quarter of the cycle is 6 hours
	assert(near(DayCycle.ClockAt(600, CONFIG), 9))
	assert(near(DayCycle.ClockAt(375, CONFIG), 0)) -- 9 + 15 hours wraps to midnight
end

tests["daylight is full at noon and zero at midnight"] = function()
	assert(DayCycle.Daylight(12) == 1)
	assert(DayCycle.Daylight(0) == 0)
	assert(DayCycle.Daylight(23) == 0)
end

tests["dawn and dusk blend smoothly"] = function()
	local dawn = DayCycle.Daylight(6)
	local dusk = DayCycle.Daylight(18)
	assert(dawn > 0 and dawn < 1, `dawn {dawn}`)
	assert(dusk > 0 and dusk < 1, `dusk {dusk}`)
	assert(DayCycle.Daylight(5.5) < DayCycle.Daylight(6.5))
	assert(DayCycle.Daylight(17.5) > DayCycle.Daylight(18.5))
end

tests["night lights follow daylight"] = function()
	assert(DayCycle.IsNight(0) == true)
	assert(DayCycle.IsNight(12) == false)
	assert(DayCycle.IsNight(19.5) == true)
	assert(DayCycle.IsNight(6.9) == false)
end

return tests
