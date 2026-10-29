--!strict
local Players = game:GetService("Players")

export type ComponentCounts = {
	FrontendUnits: number,
	BackendEndpoints: number,
	DatabaseTables: number,
	PromptTokens: number,
}

export type StartupData = {
	Cash: number,
	Valuation: number,
	Components: ComponentCounts,
}

local STARTING_CASH = 0
local STARTING_VALUATION = 1.0
local MAX_PERFORMANCE_SCORE = 2.0
local MAX_INCREMENT_AMOUNT = 100

local COMPONENT_TYPES: { [string]: boolean } = {
	FrontendUnits = true,
	BackendEndpoints = true,
	DatabaseTables = true,
	PromptTokens = true,
}

local StartupDataModule = {}

local sessions: { [Player]: StartupData } = {}

local function newComponentCounts(): ComponentCounts
	return {
		FrontendUnits = 0,
		BackendEndpoints = 0,
		DatabaseTables = 0,
		PromptTokens = 0,
	}
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function totalComponents(components: ComponentCounts): number
	return components.FrontendUnits + components.BackendEndpoints + components.DatabaseTables + components.PromptTokens
end

local function onPlayerAdded(player: Player)
	sessions[player] = {
		Cash = STARTING_CASH,
		Valuation = STARTING_VALUATION,
		Components = newComponentCounts(),
	}
end

local function onPlayerRemoving(player: Player)
	sessions[player] = nil
end

-- Returns a copy; callers cannot mutate session state through it.
function StartupDataModule.GetSnapshot(player: Player): StartupData?
	local data = sessions[player]
	if not data then
		return nil
	end

	return {
		Cash = data.Cash,
		Valuation = data.Valuation,
		Components = table.clone(data.Components),
	}
end

function StartupDataModule.GetTotalComponents(player: Player): number
	local data = sessions[player]
	if not data then
		return 0
	end
	return totalComponents(data.Components)
end

-- Returns false (and changes nothing) for unknown players, unknown component names,
-- or amounts that are not whole numbers in 1..MAX_INCREMENT_AMOUNT.
function StartupDataModule.IncrementComponent(player: Player, componentType: string, amount: number): boolean
	local data = sessions[player]
	if not data or COMPONENT_TYPES[componentType] ~= true then
		return false
	end
	if not isFiniteNumber(amount) or amount < 1 or amount > MAX_INCREMENT_AMOUNT or amount % 1 ~= 0 then
		return false
	end

	-- componentType is validated against COMPONENT_TYPES above, so the dynamic key is safe.
	local counts = data.Components :: any
	counts[componentType] += amount
	return true
end

-- payout = totalComponents * Valuation * performanceScore. Awards the cash, resets all
-- components to 0 and returns the payout. Invalid scores or unknown players pay 0 and change nothing.
function StartupDataModule.ProcessDeploymentPayout(player: Player, performanceScore: number): number
	local data = sessions[player]
	if not data or not isFiniteNumber(performanceScore) or performanceScore < 0 then
		return 0
	end

	local score = math.min(performanceScore, MAX_PERFORMANCE_SCORE)
	local payout = totalComponents(data.Components) * data.Valuation * score
	data.Cash += payout
	data.Components = newComponentCounts()
	return payout
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

return StartupDataModule
