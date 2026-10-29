--!strict
local Economy = require("../src/ReplicatedStorage/Shared/Economy")
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")

local RECIPE = GameConfig.RECIPES.LandingPage

local function counts(s: number, a: number, b: number, c: number): Economy.GradeCounts
	return { S = s, A = a, B = b, C = c }
end

local function empty(): Economy.Inventory
	return Economy.EmptyInventory(GameConfig.COMPONENTS)
end

local tests = {}

tests["total and average"] = function()
	local inv = empty()
	inv.FrontendUnits = counts(1, 0, 0, 1)
	assert(Economy.TotalUnits(inv) == 2)
	assert(Economy.AverageQuality(inv) == 1.5)
	assert(Economy.AverageQuality(empty()) == 0)
end

tests["recipe"] = function()
	local inv = empty()
	inv.FrontendUnits = counts(0, 0, 0, 1)
	assert(Economy.MeetsRecipe(inv, RECIPE) == false)
	inv.FrontendUnits = counts(0, 0, 0, 2)
	inv.BackendEndpoints = counts(0, 0, 0, 1)
	inv.DatabaseTables = counts(0, 0, 0, 1)
	inv.PromptTokens = counts(0, 0, 0, 1)
	assert(Economy.MeetsRecipe(inv, RECIPE) == true)
end

tests["add unit replaces a C"] = function()
	local inv = empty()
	inv.FrontendUnits = counts(0, 0, 0, 1)
	local upgraded = Economy.AddUnit(inv, "FrontendUnits", "A")
	assert(upgraded.FrontendUnits.A == 1 and upgraded.FrontendUnits.C == 0)
	local stacked = Economy.AddUnit(inv, "FrontendUnits", "C")
	assert(stacked.FrontendUnits.C == 2)
	assert(inv.FrontendUnits.C == 1 and inv.FrontendUnits.A == 0, "input mutated")
end

tests["hires fill to recipe"] = function()
	local filled = Economy.ApplyHires(empty(), RECIPE, { FrontendUnits = true })
	assert(filled.FrontendUnits.C == 2)
	assert(Economy.TotalUnits(filled) == 2)
end

tests["score bounds"] = function()
	assert(Economy.PerformanceScore(1, 1, 30) == 2)
	assert(Economy.PerformanceScore(0, 0, 0) == 0)
	assert(math.abs(Economy.PerformanceScore(0 / 0, 2, -5) - 0.6) < 1e-9)
end

tests["payout"] = function()
	assert(Economy.Payout(5, 1.0, 1.0, 20) == 100)
	assert(Economy.Payout(5, 1.0, 9, 20) == 200)
end

tests["valuation gain"] = function()
	assert(math.abs(Economy.ValuationGain(1) - 0.05) < 1e-9)
	assert(math.abs(Economy.ValuationGain(9) - 0.1) < 1e-9)
end

tests["clients unlock"] = function()
	assert(#Economy.AvailableClients(GameConfig.CLIENTS, 0) == 1)
	assert(#Economy.AvailableClients(GameConfig.CLIENTS, 4) == 3)
end

tests["gear"] = function()
	local rules, preview = Economy.ApplyGear(
		GameConfig.BURST_RULES,
		{ MechanicalKeyboard = true, ModelV2 = true },
		GameConfig.GEAR
	)
	assert(rules.TimeLimit == 12)
	assert(rules.ForgivenEditsPerBurst == 1)
	assert(preview == false)
	assert(GameConfig.BURST_RULES.TimeLimit == 10, "base rules mutated")
	local _, monitorPreview = Economy.ApplyGear(GameConfig.BURST_RULES, { SecondMonitor = true }, GameConfig.GEAR)
	assert(monitorPreview == true)
end

return tests
