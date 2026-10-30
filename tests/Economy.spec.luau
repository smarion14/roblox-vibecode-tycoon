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

tests["build adds while the job still needs the part"] = function()
	local inv = empty()
	inv.FrontendUnits = counts(0, 0, 0, 1)
	local built = Economy.BuildUnit(inv, "FrontendUnits", "B", 2)
	assert(built.Outcome == "Added")
	assert(built.Inventory.FrontendUnits.B == 1 and built.Inventory.FrontendUnits.C == 1)
	assert(inv.FrontendUnits.B == 0, "input mutated")
end

tests["build on a complete part upgrades the worst one"] = function()
	local inv = empty()
	inv.FrontendUnits = counts(0, 0, 1, 1)
	local built = Economy.BuildUnit(inv, "FrontendUnits", "A", 2)
	assert(built.Outcome == "Upgraded" and built.Replaced == "C")
	local grades = built.Inventory.FrontendUnits
	assert(grades.A == 1 and grades.B == 1 and grades.C == 0)
	assert(Economy.TotalUnits(built.Inventory) == 2, "an upgrade must never add a part")
end

tests["build that isn't better keeps what you have"] = function()
	local inv = empty()
	inv.FrontendUnits = counts(0, 0, 2, 0)
	local same = Economy.BuildUnit(inv, "FrontendUnits", "B", 2)
	assert(same.Outcome == "Kept" and same.Inventory.FrontendUnits.B == 2)
	local worse = Economy.BuildUnit(inv, "FrontendUnits", "C", 2)
	assert(worse.Outcome == "Kept" and worse.Inventory.FrontendUnits.C == 0)
end

tests["worst grade of a part"] = function()
	local inv = empty()
	assert(Economy.WorstGrade(inv, "FrontendUnits") == nil)
	inv.FrontendUnits = counts(1, 0, 1, 0)
	assert(Economy.WorstGrade(inv, "FrontendUnits") == "B")
end

tests["score bounds"] = function()
	assert(Economy.PerformanceScore(1, 1, 30) == 2)
	-- a battle has roughly 15-20 squashes, so a 15 streak earns full combo credit
	assert(Economy.PerformanceScore(1, 1, 15) == 2)
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

tests["clients by act"] = function()
	local clients = GameConfig.CLIENTS
	assert(#Economy.AvailableClients(clients, 1, 0) == 1)
	assert(#Economy.AvailableClients(clients, 1, 4) == 3)
	local act2 = Economy.AvailableClients(clients, 2, 0)
	assert(#act2 == 1 and act2[1].Id == "PocketFit")
	assert(#Economy.AvailableClients(clients, 2, 4) == 3)
end

tests["gear"] = function()
	local rules, preview = Economy.ApplyGear(
		GameConfig.BURST_RULES,
		{ MechanicalKeyboard = true, ModelV2 = true },
		GameConfig.GEAR
	)
	assert(rules.TimeLimit == GameConfig.BURST_RULES.TimeLimit + 2)
	assert(rules.ForgivenEditsPerBurst == 1)
	assert(preview == false)
	assert(rules ~= GameConfig.BURST_RULES, "base rules mutated")
	local _, monitorPreview = Economy.ApplyGear(GameConfig.BURST_RULES, { SecondMonitor = true }, GameConfig.GEAR)
	assert(monitorPreview == true)
end

tests["performance grade"] = function()
	assert(Economy.PerformanceGrade(2) == "S")
	assert(Economy.PerformanceGrade(1.8) == "S")
	assert(Economy.PerformanceGrade(1.79) == "A")
	assert(Economy.PerformanceGrade(1.5) == "A")
	assert(Economy.PerformanceGrade(1.1) == "B")
	assert(Economy.PerformanceGrade(1.09) == "C")
	assert(Economy.PerformanceGrade(0 / 0) == "C")
end

return tests
