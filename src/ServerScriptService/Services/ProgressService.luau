--!strict
-- Story beats and the Act 1 milestone: intro on first join, sibling texts after deploys, paying rent ends Act 1.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local StoryText = require(Shared:WaitForChild("StoryText"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local ProgressService = {}

local function beat(player: Player, kind: string, payload: any)
	RemoteManager.FireClient(RemoteNames.StoryBeat, player, kind, payload)
end

local function onLoaded(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if save and not save.SeenIntro then
		beat(player, "Intro", StoryText.INTRO)
	end
end

local function onIntroSeen(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if save and not save.SeenIntro then
		StartupDataModule.Update(player, function(current)
			current.SeenIntro = true
		end)
	end
end

local function onDeployed(player: Player, _payout: number)
	local save = StartupDataModule.GetSnapshot(player)
	if save then
		local index = math.clamp(save.DeploysShipped, 1, #StoryText.SIBLING_TEXTS)
		beat(player, "SiblingText", StoryText.SIBLING_TEXTS[index])
	end
end

local function onSibling(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end
	if save.RentPaid then
		beat(player, "Act1Complete", StoryText.ACT1_COMPLETE)
		return
	end
	if save.Cash < GameConfig.RENT_GOAL then
		local remaining = GameConfig.RENT_GOAL - save.Cash
		RemoteManager.FireClient(RemoteNames.Notice, player, `"Rent's ${GameConfig.RENT_GOAL}. You're ${remaining} short."`)
		return
	end

	StartupDataModule.Update(player, function(current)
		current.Cash -= GameConfig.RENT_GOAL
		current.RentPaid = true
		current.StoryFlags.Act1Complete = true
	end)
	beat(player, "RentPaid", { Lines = StoryText.RENT_PAID, Ending = StoryText.ACT1_COMPLETE })
end

function ProgressService.Init() end

function ProgressService.Start()
	StartupDataModule.OnPlayerLoaded(onLoaded)
	AssemblyService.OnDeployed(onDeployed)
	PlotService.OnPromptTriggered("Sibling", onSibling)
	RemoteManager.Listen(RemoteNames.IntroSeen, onIntroSeen, 2, 1)
end

return ProgressService
