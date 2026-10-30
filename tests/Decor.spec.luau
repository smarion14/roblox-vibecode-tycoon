--!strict
local Decor = require("../src/ReplicatedStorage/Shared/Decor")

local ZONE = { CellsX = 14, CellsZ = 12 }
local DECOR: { [string]: Decor.ItemDef } = {
	Plant = { Name = "Plant", Price = 60, Size = { X = 1, Z = 1 } },
	Rug = { Name = "Rug", Price = 90, Size = { X = 3, Z = 2 } },
	CoffeeMachine = { Name = "Coffee Machine", Price = 400, Size = { X = 1, Z = 1 }, Perk = { Speed = 0.2 } },
	ArcadeCabinet = { Name = "Arcade Cabinet", Price = 900, Size = { X = 1, Z = 1 }, Perk = { Speed = 0.1 } },
}

local function canPlace(placed: { Decor.Placement }, id: string, x: number, z: number, r: number, ignore: number?): (boolean, string?)
	return Decor.CanPlace(placed, DECOR, ZONE, { Id = id, X = x, Z = z, R = r }, ignore)
end

local tests = {}

tests["places inside the zone"] = function()
	assert(canPlace({}, "Rug", 0, 0, 0))
end

tests["rejects off-grid and outside"] = function()
	local ok, reason = canPlace({}, "Rug", -1, 0, 0)
	assert(not ok and reason == "Outside the zone")
	ok, reason = canPlace({}, "Rug", 12, 0, 0)
	assert(not ok and reason == "Outside the zone")
	ok, reason = canPlace({}, "Rug", 0.5, 0, 0)
	assert(not ok and reason == "Off the grid")
	ok, reason = canPlace({}, "Rug", 0, 0, 45)
	assert(not ok and reason == "Bad rotation")
	ok, reason = canPlace({}, "Nope", 0, 0, 0)
	assert(not ok and reason == "Unknown item")
end

tests["rotation swaps the footprint"] = function()
	assert(canPlace({}, "Rug", 11, 0, 90))
	assert(not canPlace({}, "Rug", 12, 0, 0))
	local w, d = Decor.Footprint(DECOR.Rug, 270)
	assert(w == 2 and d == 3)
end

tests["rejects overlaps"] = function()
	local placed: { Decor.Placement } = { { Id = "Plant", X = 2, Z = 2, R = 0 } }
	local ok, reason = canPlace(placed, "Rug", 1, 1, 0)
	assert(not ok and reason == "Overlaps")
	assert(canPlace(placed, "Plant", 3, 2, 0))
end

tests["one of each perk"] = function()
	local placed: { Decor.Placement } = { { Id = "CoffeeMachine", X = 0, Z = 0, R = 0 } }
	local ok, reason = canPlace(placed, "CoffeeMachine", 5, 5, 0)
	assert(not ok and reason == "Already have one")
	assert(canPlace(placed, "CoffeeMachine", 5, 5, 0, 1))
end

tests["perks follow what is placed"] = function()
	local perks = Decor.Perks({ { Id = "CoffeeMachine", X = 0, Z = 0, R = 0 }, { Id = "ArcadeCabinet", X = 2, Z = 0, R = 0 } }, DECOR)
	assert(math.abs(perks.Speed - 0.3) < 1e-9 and perks.GradeAChance == 0)
	local none = Decor.Perks({}, DECOR)
	assert(none.Speed == 0 and none.GradeAChance == 0)
end

tests["office has a cap"] = function()
	local placed: { Decor.Placement } = {}
	for i = 1, 200 do
		table.insert(placed, { Id = "Plant", X = i % 14, Z = 0, R = 0 })
	end
	local ok, reason = canPlace(placed, "Plant", 0, 5, 0)
	assert(not ok and reason == "Office is full")
end

return tests
