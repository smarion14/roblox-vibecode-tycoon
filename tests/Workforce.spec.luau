--!strict
local Workforce = require("../src/ReplicatedStorage/Shared/Workforce")

local ORDER = { "FrontendUnits", "BackendEndpoints" }
local NO_BONUS: Workforce.Bonuses = { Speed = 0, GradeAChance = 0 }

local tests = {}

tests["build time drops with speed perks"] = function()
	assert(Workforce.BuildSeconds(25, NO_BONUS) == 25)
	assert(math.abs(Workforce.BuildSeconds(25, { Speed = 0.3, GradeAChance = 0 }) - 25 / 1.3) < 1e-9)
end

tests["only hired roles that still need parts work"] = function()
	local recipe = { FrontendUnits = 2, BackendEndpoints = 2 }
	local hires = { FrontendUnits = true, BackendEndpoints = true }
	local needs = Workforce.Needs(ORDER, recipe, { FrontendUnits = 2, BackendEndpoints = 1 }, hires)
	assert(#needs == 1 and needs[1] == "BackendEndpoints")
end

tests["employees stop once the need is met"] = function()
	local recipe = { FrontendUnits = 2, BackendEndpoints = 2 }
	local hires = { FrontendUnits = true, BackendEndpoints = true }
	assert(#Workforce.Needs(ORDER, recipe, { FrontendUnits = 2, BackendEndpoints = 2 }, hires) == 0)
end

tests["a part finishes every build time"] = function()
	local progress: { [string]: number } = {}
	assert(#Workforce.Step(progress, { "FrontendUnits" }, 24, 25) == 0)
	local done = Workforce.Step(progress, { "FrontendUnits" }, 1.5, 25)
	assert(#done == 1 and done[1] == "FrontendUnits")
	assert(math.abs((progress.FrontendUnits :: number) - 0.5) < 1e-9)
end

tests["idle roles reset"] = function()
	local progress: { [string]: number } = { FrontendUnits = 0.5 }
	Workforce.Step(progress, {}, 1, 25)
	assert(progress.FrontendUnits == 0)
end

tests["lounge gives a chance of A"] = function()
	local lounge: Workforce.Bonuses = { Speed = 0, GradeAChance = 0.15 }
	assert(Workforce.RollGrade(lounge, 0.1) == "A")
	assert(Workforce.RollGrade(lounge, 0.2) == "B")
	assert(Workforce.RollGrade(NO_BONUS, 0) == "B")
end

return tests
