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

function Economy.AddUnit(inv: Inventory, component: string, grade: Grade): Inventory
	local result = copyInventory(inv)
	local grades = result[component] or { S = 0, A = 0, B = 0, C = 0 }
	result[component] = grades

	-- A better unit replaces a C (a hire's work, or a sloppy earlier burst) instead of stacking on it.
	if grade ~= "C" and grades.C > 0 then
		grades.C -= 1
	end
	grades[grade] += 1
	return result
end

function Economy.ApplyHires(inv: Inventory, recipe: Recipe, hired: { [string]: boolean }): Inventory
	local result = copyInventory(inv)
	for component, isHired in hired do
		local needed = recipe[component]
		if not isHired or not needed then
			continue
		end
		local grades = result[component] or { S = 0, A = 0, B = 0, C = 0 }
		result[component] = grades
		grades.C += math.max(0, needed - unitCount(grades))
	end
	return result
end

function Economy.PerformanceScore(moodRatio: number, accuracy: number, maxCombo: number): number
	local comboRatio = clamp01(maxCombo / COMBO_FOR_FULL_CREDIT)
	return MAX_SCORE * (0.5 * clamp01(moodRatio) + 0.3 * clamp01(accuracy) + 0.2 * comboRatio)
end

function Economy.Payout(totalUnits: number, valuation: number, score: number, tierMultiplier: number): number
	return math.floor(totalUnits * valuation * math.clamp(score, 0, MAX_SCORE) * tierMultiplier)
end

function Economy.ValuationGain(score: number): number
	return VALUATION_GAIN_PER_SCORE * math.clamp(score, 0, MAX_SCORE)
end

function Economy.AvailableClients(clients: { ClientDef }, deploysShipped: number): { ClientDef }
	local available: { ClientDef } = {}
	for _, client in clients do
		if deploysShipped >= client.UnlockAtDeploys then
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
