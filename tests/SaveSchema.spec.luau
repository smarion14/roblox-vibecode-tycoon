--!strict
local SaveSchema = require("../src/ReplicatedStorage/Shared/SaveSchema")

local CATALOG: SaveSchema.SaveCatalog = {
	Components = { "FrontendUnits", "BackendEndpoints", "DatabaseTables", "PromptTokens" },
	GearIds = { "MechanicalKeyboard", "SecondMonitor", "ModelV2" },
	HireIds = { "FrontendUnits", "BackendEndpoints", "DatabaseTables", "PromptTokens" },
	ClientIds = { "PawsAndSuds", "RollingTaco", "CornerBakery" },
	StartingValuation = 1.0,
}

local tests = {}

tests["sanitize nil gives default"] = function()
	local save = SaveSchema.Sanitize(nil, CATALOG)
	assert(save.Version == SaveSchema.VERSION)
	assert(save.Cash == 0 and save.Valuation == 1.0 and save.Act == 1)
	assert(save.RentPaid == false and save.SeenIntro == false)
	assert(save.Inventory.FrontendUnits.S == 0)
	assert(save.LockJobId == nil and save.LockTime == 0)
end

tests["negative and NaN cash become 0"] = function()
	assert(SaveSchema.Sanitize({ Cash = -5 }, CATALOG).Cash == 0)
	assert(SaveSchema.Sanitize({ Cash = 0 / 0 }, CATALOG).Cash == 0)
	assert(SaveSchema.Sanitize({ Cash = math.huge }, CATALOG).Cash == 0)
	assert(SaveSchema.Sanitize({ Cash = "lots" }, CATALOG).Cash == 0)
	assert(SaveSchema.Sanitize({ Cash = 12.9 }, CATALOG).Cash == 12)
end

tests["valuation floor"] = function()
	assert(SaveSchema.Sanitize({ Valuation = 0.2 }, CATALOG).Valuation == 1.0)
	assert(SaveSchema.Sanitize({ Valuation = 1.35 }, CATALOG).Valuation == 1.35)
end

tests["unknown gear dropped"] = function()
	local save = SaveSchema.Sanitize({ Gear = { Jetpack = true, MechanicalKeyboard = true } }, CATALOG)
	assert(save.Gear.MechanicalKeyboard == true)
	assert(save.Gear.Jetpack == nil)
end

tests["grade counts floored"] = function()
	local save = SaveSchema.Sanitize({ Inventory = { FrontendUnits = { S = 2.7 }, Hats = { S = 9 } } }, CATALOG)
	assert(save.Inventory.FrontendUnits.S == 2)
	assert(save.Inventory.FrontendUnits.C == 0)
	assert(save.Inventory.Hats == nil)
end

tests["active job kept only if known"] = function()
	assert(SaveSchema.Default(CATALOG).ActiveJobId == nil)
	assert(SaveSchema.Sanitize({ ActiveJobId = "RollingTaco" }, CATALOG).ActiveJobId == "RollingTaco")
	assert(SaveSchema.Sanitize({ ActiveJobId = "EvilCorp" }, CATALOG).ActiveJobId == nil)
	assert(SaveSchema.Sanitize({ ActiveJobId = 42 }, CATALOG).ActiveJobId == nil)
end

tests["act clamped"] = function()
	assert(SaveSchema.Sanitize({ Act = 9 }, CATALOG).Act == 3)
	assert(SaveSchema.Sanitize({ Act = -1 }, CATALOG).Act == 1)
end

tests["unknown top level fields dropped"] = function()
	local save = SaveSchema.Sanitize({ Admin = true }, CATALOG) :: any
	assert(save.Admin == nil)
end

tests["resolve load"] = function()
	assert(SaveSchema.ResolveLoad(false, nil) == "Fail")
	assert(SaveSchema.ResolveLoad(false, {}) == "Fail")
	assert(SaveSchema.ResolveLoad(true, nil) == "UseDefault")
	assert(SaveSchema.ResolveLoad(true, {}) == "UseRaw")
end

tests["lock claims"] = function()
	local free = SaveSchema.Default(CATALOG)
	assert(SaveSchema.TryClaimLock(free, "job-a", 1000, 120) == true)
	assert(free.LockJobId == "job-a" and free.LockTime == 1000)

	local held = SaveSchema.Default(CATALOG)
	held.LockJobId = "job-b"
	held.LockTime = 990
	assert(SaveSchema.TryClaimLock(held, "job-a", 1000, 120) == false)
	assert(held.LockJobId == "job-b" and held.LockTime == 990, "failed claim mutated save")

	local stale = SaveSchema.Default(CATALOG)
	stale.LockJobId = "job-b"
	stale.LockTime = 879
	assert(SaveSchema.TryClaimLock(stale, "job-a", 1000, 120) == true)

	local mine = SaveSchema.Default(CATALOG)
	mine.LockJobId = "job-a"
	mine.LockTime = 999
	assert(SaveSchema.TryClaimLock(mine, "job-a", 1000, 120) == true)
end

return tests
