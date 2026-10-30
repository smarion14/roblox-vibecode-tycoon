--!strict
-- Pure: no requires, no Roblox APIs. Placement rules shared by the server DecorService and the client
-- decorate mode, so a preview is only ever green when the server would accept it.

export type Placement = { Id: string, X: number, Z: number, R: number }
export type ItemDef = {
	Name: string,
	Price: number,
	Size: { X: number, Z: number },
	Perk: { Speed: number?, GradeAChance: number? }?,
}
export type Zone = { CellsX: number, CellsZ: number }
export type Perks = { Speed: number, GradeAChance: number }

-- shortcut: mirrors GameConfig.DECOR_MAX_ITEMS (pure modules cannot require); unify if require-by-string is adopted
local MAX_ITEMS = 200

local Decor = {}

Decor.MAX_ITEMS = MAX_ITEMS

function Decor.Footprint(def: ItemDef, r: number): (number, number)
	if r == 90 or r == 270 then
		return def.Size.Z, def.Size.X
	end
	return def.Size.X, def.Size.Z
end

function Decor.CanPlace(
	placed: { Placement },
	catalog: { [string]: ItemDef },
	zone: Zone,
	item: Placement,
	ignoreIndex: number?
): (boolean, string?)
	local def = catalog[item.Id]
	if not def then
		return false, "Unknown item"
	end
	local r = item.R
	if r ~= 0 and r ~= 90 and r ~= 180 and r ~= 270 then
		return false, "Bad rotation"
	end
	if math.floor(item.X) ~= item.X or math.floor(item.Z) ~= item.Z then
		return false, "Off the grid"
	end

	local w, d = Decor.Footprint(def, r)
	if item.X < 0 or item.Z < 0 or item.X + w > zone.CellsX or item.Z + d > zone.CellsZ then
		return false, "Outside the zone"
	end

	local count = 0
	for index, other in placed do
		if index == ignoreIndex then
			continue
		end
		count += 1
		if def.Perk and other.Id == item.Id then
			return false, "Already have one"
		end
		local otherDef = catalog[other.Id]
		if otherDef then
			local ow, od = Decor.Footprint(otherDef, other.R)
			if item.X < other.X + ow and other.X < item.X + w and item.Z < other.Z + od and other.Z < item.Z + d then
				return false, "Overlaps"
			end
		end
	end
	if count >= MAX_ITEMS then
		return false, "Office is full"
	end
	return true, nil
end

function Decor.Perks(placed: { Placement }, catalog: { [string]: ItemDef }): Perks
	local total: Perks = { Speed = 0, GradeAChance = 0 }
	for _, entry in placed do
		local perk = if catalog[entry.Id] then catalog[entry.Id].Perk else nil
		if perk then
			total.Speed += perk.Speed or 0
			total.GradeAChance += perk.GradeAChance or 0
		end
	end
	return total
end

return Decor
