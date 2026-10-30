--!strict
-- Pure rules for hired employees building parts on their own. No Roblox APIs.
local Workforce = {}

export type Bonuses = { Speed: number, GradeAChance: number }

function Workforce.BuildSeconds(base: number, bonuses: Bonuses): number
	return base / (1 + bonuses.Speed)
end

-- Hired roles that still need parts for the recipe, in component order.
function Workforce.Needs(
	order: { string },
	recipe: { [string]: number },
	have: { [string]: number },
	hires: { [string]: boolean }
): { string }
	local needs: { string } = {}
	for _, role in order do
		if hires[role] and (have[role] or 0) < (recipe[role] or 0) then
			table.insert(needs, role)
		end
	end
	return needs
end

-- Advances progress (seconds) for working roles, resets the rest, returns the roles that finished a part.
function Workforce.Step(progress: { [string]: number }, working: { string }, dt: number, buildSeconds: number): { string }
	local isWorking: { [string]: boolean } = {}
	local finished: { string } = {}
	for _, role in working do
		isWorking[role] = true
		local value = (progress[role] or 0) + dt
		if value >= buildSeconds then
			value -= buildSeconds
			table.insert(finished, role)
		end
		progress[role] = value
	end
	for role in progress do
		if not isWorking[role] then
			progress[role] = 0
		end
	end
	return finished
end

function Workforce.RollGrade(bonuses: Bonuses, roll: number): string
	return if roll < bonuses.GradeAChance then "A" else "B"
end

return Workforce
