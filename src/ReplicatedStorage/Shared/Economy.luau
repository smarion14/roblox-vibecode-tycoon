--!strict
-- Pure: no requires, no Roblox APIs. Inventory, payout, valuation, gear and hire rules.

-- shortcut: duplicated literal type, pure modules cannot require each other; unify if require-by-string is adopted
export type Grade = "S" | "A" | "B" | "C"
export type GradeCounts = { S: number, A: number, B: number, C: number }
export type Inventory = { [string]: GradeCounts }
export type Recipe = { [string]: number }

export type ClientDef = {
	Id: string,
	Name: string,
	Project: string,
	TierMultiplier: number,
	UnlockAtDeploys: number,
	Act: number,
}

export type GearDef = {
	Name: string,
	Price: number,
	TimeBonus: number?,
	PreviewNext: boolean?,
	ForgiveEdits: number?,
}

export type BurstRules = {
	TimeLimit: number,
	LatencyGrace: number,
	MaxCharsPerSecond: number,
	ForgivenEditsPerBurst: number,
	CleanAccuracy: number,
	CleanBonus: number,
	BonusPerPrompt: number,
	ErrorPenalty: number,
}

local GRADE_VALUE: { [string]: number } = { S = 3, A = 2, B = 1, C = 0 }
local COMBO_FOR_FULL_CREDIT = 15
local VALUATION_GAIN_PER_SCORE = 0.05
local MAX_SCORE = 2

local Economy = {}

local function unitCount(grades: GradeCounts): number
	return grades.S + grades.A + grades.B + grades.C
end

local function clamp01(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

local function copyInventory(inv: Inventory): Inventory
	local copy: Inventory = {}
	for component, grades in inv do
		copy[component] = table.clone(grades)
	end
	return copy
end

function Economy.EmptyInventory(components: { string }): Inventory
	local inv: Inventory = {}
	for _, component in components do
		inv[component] = { S = 0, A = 0, B = 0, C = 0 }
	end
	return inv
end

function Economy.TotalUnits(inv: Inventory): number
	local total = 0
	for _, grades in inv do
		total += unitCount(grades)
	end
	return total
end

function Economy.AverageQuality(inv: Inventory): number
	local total, weighted = 0, 0
	for _, grades in inv do
		total += unitCount(grades)
		weighted += grades.S * GRADE_VALUE.S + grades.A * GRADE_VALUE.A + grades.B * GRADE_VALUE.B
	end
	if total == 0 then
		return 0
	end
	return weighted / total
end

function Economy.MeetsRecipe(inv: Inventory, recipe: Recipe): boolean
	for component, needed in recipe do
		local grades = inv[component]
		if not grades or unitCount(grades) < needed then
			return false
		end
	end
	return true
end

export type BuildOutcome = "Added" | "Upgraded" | "Kept"
export type BuildResult = { Inventory: Inventory, Outcome: BuildOutcome, Replaced: Grade? }

local WORST_FIRST: { Grade } = { "C", "B", "A", "S" }

-- Lowest grade currently held for a component, or nil if there are none.
function Economy.WorstGrade(inv: Inventory, component: string): Grade?
	local grades = inv[component]
	if not grades then
		return nil
	end
	for _, grade in WORST_FIRST do
		if grades[grade] > 0 then
			return grade :: Grade
		end
	end
	return nil
end

-- Upgrade, don't add: below the job's requirement a build adds a part; once the part is complete a build
-- replaces the worst one if it is better, and otherwise changes nothing. Returns a new inventory.
function Economy.BuildUnit(inv: Inventory, component: string, grade: Grade, needed: number): BuildResult
	local result = copyInventory(inv)
	local grades = result[component] or { S = 0, A = 0, B = 0, C = 0 }
	result[component] = grades

	if unitCount(grades) < needed then
		grades[grade] += 1
		return { Inventory = result, Outcome = "Added", Replaced = nil }
	end

	local worst: Grade? = Economy.WorstGrade(result, component)
	if worst and GRADE_VALUE[grade] > GRADE_VALUE[worst] then
		grades[worst] -= 1
		grades[grade] += 1
		return { Inventory = result, Outcome = "Upgraded", Replaced = worst :: Grade }
	end
	return { Inventory = result, Outcome = "Kept", Replaced = nil }
end

function Economy.PerformanceScore(moodRatio: number, accuracy: number, maxCombo: number): number
	local comboRatio = clamp01(maxCombo / COMBO_FOR_FULL_CREDIT)
	return MAX_SCORE * (0.5 * clamp01(moodRatio) + 0.3 * clamp01(accuracy) + 0.2 * comboRatio)
end

-- Letter grade for a deploy's performance score (0-2), shown on the results screen.
function Economy.PerformanceGrade(score: number): Grade
	if score ~= score then
		return "C"
	elseif score >= 1.8 then
		return "S"
	elseif score >= 1.5 then
		return "A"
	elseif score >= 1.1 then
		return "B"
	end
	return "C"
end

function Economy.Payout(totalUnits: number, valuation: number, score: number, tierMultiplier: number): number
	return math.floor(totalUnits * valuation * math.clamp(score, 0, MAX_SCORE) * tierMultiplier)
end

function Economy.ValuationGain(score: number): number
	return VALUATION_GAIN_PER_SCORE * math.clamp(score, 0, MAX_SCORE)
end

-- Clients of the player's current act whose unlock count is met (deploys shipped within this act).
function Economy.AvailableClients(clients: { ClientDef }, act: number, actDeploys: number): { ClientDef }
	local available: { ClientDef } = {}
	for _, client in clients do
		if client.Act == act and actDeploys >= client.UnlockAtDeploys then
			table.insert(available, client)
		end
	end
	return available
end

function Economy.ApplyGear(
	base: BurstRules,
	owned: { [string]: boolean },
	gear: { [string]: GearDef }
): (BurstRules, boolean)
	local rules = table.clone(base)
	local previewNext = false
	for gearId, isOwned in owned do
		local def = gear[gearId]
		if not isOwned or not def then
			continue
		end
		rules.TimeLimit += def.TimeBonus or 0
		rules.ForgivenEditsPerBurst += def.ForgiveEdits or 0
		previewNext = previewNext or def.PreviewNext == true
	end
	return rules, previewNext
end

return Economy
