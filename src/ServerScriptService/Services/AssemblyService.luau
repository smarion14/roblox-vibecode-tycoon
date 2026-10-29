--!strict
-- Client jobs and deploy settlement. A job sets the recipe; shipping consumes every built unit and pays out.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleState = require(Shared:WaitForChild("BattleState"))
local Economy = require(Shared:WaitForChild("Economy"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

type ClientDef = GameConfig.ClientDef

local AssemblyService = {}

local deployedCallbacks: { (player: Player, payout: number) -> () } = {}

local function findClient(clientId: string?): ClientDef?
	for _, client in GameConfig.CLIENTS do
		if client.Id == clientId then
			return client
		end
	end
	return nil
end

local function notice(player: Player, text: string)
	RemoteManager.FireClient(RemoteNames.Notice, player, text)
end

function AssemblyService.GetActiveJob(player: Player): ClientDef?
	local save = StartupDataModule.GetSnapshot(player)
	return if save then findClient(save.ActiveJobId) else nil
end

function AssemblyService.SettleDeploy(player: Player, result: BattleState.BattleResult): number
	local job = AssemblyService.GetActiveJob(player)
	if result.Status ~= "Shipped" or not job then
		return 0
	end

	local payout = 0
	StartupDataModule.Update(player, function(save)
		local score = Economy.PerformanceScore(result.MoodRatio, result.Accuracy, result.MaxCombo)
		payout = Economy.Payout(Economy.TotalUnits(save.Inventory), save.Valuation, score, job.TierMultiplier)
		save.Cash += payout
		save.Valuation += Economy.ValuationGain(score)
		save.DeploysShipped += 1
		save.Inventory = Economy.EmptyInventory(GameConfig.COMPONENTS)
		save.ActiveJobId = nil
	end)

	for _, callback in deployedCallbacks do
		task.spawn(callback, player, payout)
	end
	return payout
end

function AssemblyService.OnDeployed(callback: (player: Player, payout: number) -> ())
	table.insert(deployedCallbacks, callback)
end

local function onAcceptJob(player: Player, clientId: any)
	if type(clientId) ~= "string" or #clientId > GameConfig.MAX_REMOTE_STRING then
		return
	end
	local save = StartupDataModule.GetSnapshot(player)
	if not save or StartupDataModule.GetActivity(player) ~= "Idle" then
		return
	end
	if save.ActiveJobId then
		notice(player, "Finish your current job first.")
		return
	end

	local client: ClientDef? = nil
	for _, available in Economy.AvailableClients(GameConfig.CLIENTS, save.DeploysShipped) do
		if available.Id == clientId then
			client = available
		end
	end
	if not client then
		return
	end

	local recipe = GameConfig.RECIPES[client.Project]
	StartupDataModule.Update(player, function(current)
		current.ActiveJobId = client.Id
		current.Inventory = Economy.ApplyHires(current.Inventory, recipe, current.Hires)
	end)
	notice(player, `New job: {client.Name}`)
end

local function onJobPhone(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end
	RemoteManager.FireClient(
		RemoteNames.OpenUI,
		player,
		"Jobs",
		Economy.AvailableClients(GameConfig.CLIENTS, save.DeploysShipped)
	)
end

function AssemblyService.Init() end

function AssemblyService.Start()
	PlotService.OnPromptTriggered("JobPhone", onJobPhone)
	RemoteManager.Listen(RemoteNames.AcceptJob, onAcceptJob)
end

return AssemblyService
