--!strict
-- Pure: no requires, no Roblox APIs. Everything loaded from a DataStore passes through Sanitize,
-- because stored data can be corrupt or from an older version.

-- shortcut: duplicated from Economy, pure modules cannot require each other; unify if require-by-string is adopted
type GradeCounts = { S: number, A: number, B: number, C: number }
type Inventory = { [string]: GradeCounts }

export type Placement = { Id: string, X: number, Z: number, R: number }

export type PlayerSave = {
	Version: number,
	Cash: number,
	Valuation: number,
	Act: number,
	DeploysShipped: number,
	RentPaid: boolean,
	SeenIntro: boolean,
	Inventory: Inventory,
	Gear: { [string]: boolean },
	Hires: { [string]: boolean },
	StoryFlags: { [string]: boolean },
	Decor: { Placement },
	ActiveJobId: string?,
	StartupName: string?,
	ActDeploys: number,
	ActGoal: number,
	LockJobId: string?,
	LockTime: number,
}

export type SaveCatalog = {
	Components: { string },
	GearIds: { string },
	HireIds: { string },
	ClientIds: { string },
	DecorIds: { string },
	StartingValuation: number,
}

export type LoadDecision = "Fail" | "UseDefault" | "UseRaw"

local MAX_ACT = 3
local MAX_NAME_CHARS = 24
-- shortcut: mirrors GameConfig.DECOR_MAX_ITEMS and the zone bound (pure modules cannot require)
local MAX_DECOR_ITEMS = 200
local MAX_DECOR_CELL = 63
local DECOR_ROTATIONS = { [0] = true, [90] = true, [180] = true, [270] = true }
local GRADES = { "S", "A", "B", "C" }

local SaveSchema = {}

SaveSchema.VERSION = 1

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function wholeNonNegative(value: any): number
	if not isFinite(value) then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function flagSet(raw: any, allowed: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return result
	end
	for _, id in allowed do
		if raw[id] == true then
			result[id] = true
		end
	end
	return result
end

-- Structural only; zone fit and overlaps are checked by DecorService on load.
local function decorList(raw: any, ids: { string }): { Placement }
	local result: { Placement } = {}
	if type(raw) ~= "table" then
		return result
	end
	for _, entry in raw do
		if #result >= MAX_DECOR_ITEMS then
			break
		end
		if type(entry) ~= "table" or type(entry.Id) ~= "string" or not table.find(ids, entry.Id) then
			continue
		end
		local x, z, r = entry.X, entry.Z, entry.R
		if
			isFinite(x) and isFinite(z)
			and x == math.floor(x) and z == math.floor(z)
			and x >= 0 and x <= MAX_DECOR_CELL and z >= 0 and z <= MAX_DECOR_CELL
			and DECOR_ROTATIONS[r]
		then
			table.insert(result, { Id = entry.Id, X = x, Z = z, R = r })
		end
	end
	return result
end

function SaveSchema.Default(catalog: SaveCatalog): PlayerSave
	local inventory: Inventory = {}
	for _, component in catalog.Components do
		inventory[component] = { S = 0, A = 0, B = 0, C = 0 }
	end

	return {
		Version = SaveSchema.VERSION,
		Cash = 0,
		Valuation = catalog.StartingValuation,
		Act = 1,
		DeploysShipped = 0,
		RentPaid = false,
		SeenIntro = false,
		Inventory = inventory,
		Gear = {},
		Hires = {},
		StoryFlags = {},
		Decor = {},
		ActiveJobId = nil,
		StartupName = nil,
		ActDeploys = 0,
		ActGoal = 0,
		LockJobId = nil,
		LockTime = 0,
	}
end

function SaveSchema.Sanitize(raw: any, catalog: SaveCatalog): PlayerSave
	local save = SaveSchema.Default(catalog)
	if type(raw) ~= "table" then
		return save
	end

	save.Cash = wholeNonNegative(raw.Cash)
	save.DeploysShipped = wholeNonNegative(raw.DeploysShipped)
	if isFinite(raw.Valuation) then
		save.Valuation = math.max(catalog.StartingValuation, raw.Valuation)
	end
	if isFinite(raw.Act) then
		save.Act = math.clamp(math.floor(raw.Act), 1, MAX_ACT)
	end
	save.RentPaid = raw.RentPaid == true
	save.SeenIntro = raw.SeenIntro == true

	if type(raw.Inventory) == "table" then
		for _, component in catalog.Components do
			local rawGrades = raw.Inventory[component]
			if type(rawGrades) ~= "table" then
				continue
			end
			local grades = save.Inventory[component] :: any
			for _, grade in GRADES do
				grades[grade] = wholeNonNegative(rawGrades[grade])
			end
		end
	end

	save.Gear = flagSet(raw.Gear, catalog.GearIds)
	save.Hires = flagSet(raw.Hires, catalog.HireIds)

	if type(raw.StoryFlags) == "table" then
		for key, value in raw.StoryFlags do
			if type(key) == "string" and value == true then
				save.StoryFlags[key] = true
			end
		end
	end

	save.Decor = decorList(raw.Decor, catalog.DecorIds)

	if type(raw.ActiveJobId) == "string" and table.find(catalog.ClientIds, raw.ActiveJobId) then
		save.ActiveJobId = raw.ActiveJobId
	end

	local nameLength = if type(raw.StartupName) == "string" then utf8.len(raw.StartupName) else nil
	if nameLength and nameLength >= 1 and nameLength <= MAX_NAME_CHARS then
		save.StartupName = raw.StartupName
	end
	save.ActDeploys = wholeNonNegative(raw.ActDeploys)
	if isFinite(raw.ActGoal) then
		save.ActGoal = math.max(0, raw.ActGoal)
	end

	if type(raw.LockJobId) == "string" then
		save.LockJobId = raw.LockJobId
	end
	if isFinite(raw.LockTime) then
		save.LockTime = raw.LockTime
	end

	return save
end

function SaveSchema.ResolveLoad(ok: boolean, raw: any): LoadDecision
	if not ok then
		return "Fail"
	elseif raw == nil then
		return "UseDefault"
	end
	return "UseRaw"
end

function SaveSchema.TryClaimLock(save: PlayerSave, jobId: string, now: number, staleAfter: number): boolean
	local holder = save.LockJobId
	if holder ~= nil and holder ~= jobId and now - save.LockTime <= staleAfter then
		return false
	end
	save.LockJobId = jobId
	save.LockTime = now
	return true
end

return SaveSchema
