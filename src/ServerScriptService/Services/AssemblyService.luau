--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))

local DEPLOY_COMPLETED_REMOTE = "DeployCompleted"

local AssemblyService = {}

function AssemblyService.HasAllComponents(player: Player): boolean
	local data = StartupDataModule.GetSnapshot(player)
	if not data then
		return false
	end

	local components = data.Components
	return components.FrontendUnits >= 1
		and components.BackendEndpoints >= 1
		and components.DatabaseTables >= 1
		and components.PromptTokens >= 1
end

-- performanceScore must come from a server-side evaluation, never straight from a client.
-- Returns the cash awarded, or nil if the player can't deploy yet.
function AssemblyService.DeployProduct(player: Player, performanceScore: number): number?
	if not AssemblyService.HasAllComponents(player) then
		return nil
	end

	local payout = StartupDataModule.ProcessDeploymentPayout(player, performanceScore)
	local data = StartupDataModule.GetSnapshot(player)
	if data then
		RemoteManager.FireClient(DEPLOY_COMPLETED_REMOTE, player, payout, data.Cash)
	end
	return payout
end

-- Create the remote up front so clients can WaitForChild it before the first deploy.
RemoteManager.GetRemote(DEPLOY_COMPLETED_REMOTE)

return AssemblyService
