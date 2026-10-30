--!strict
-- Story flow: Story.NextBeat picks the cutscene a save still owes, the client plays it and reports CutsceneDone,
-- and finishing the Act 1 ending moves the player into Act 2 and their office. Sibling texts after deploys,
-- paying rent ends Act 1, reaching the valuation goal ends Act 2.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local Story = require(Shared:WaitForChild("Story"))
local StoryText = require(Shared:WaitForChild("StoryText"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local ProgressService = {}

local function beat(player: Player, kind: string, payload: any)
	RemoteManager.FireClient(RemoteNames.StoryBeat, player, kind, payload)
end

local function storyState(save: StartupDataModule.PlayerSave): Story.StoryState
	return { Act = save.Act, SeenIntro = save.SeenIntro, RentPaid = save.RentPaid, Flags = save.StoryFlags }
end

-- Sends the cutscene this save still owes, if any, with the copy and numbers it needs.
local function sendNextBeat(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end
	local id = Story.NextBeat(storyState(save))
	if not id then
		return
	end
	beat(player, "Cutscene", {
		Id = id,
		Copy = {
			RentGoal = GameConfig.RENT_GOAL,
			ActGoal = save.ActGoal,
			Act1Intro = StoryText.ACT1_INTRO,
			Act1End = StoryText.ACT1_END,
			Act2Text = StoryText.ACT2_INTRO_TEXT,
			BrotherText = StoryText.BROTHER_TEXT_ACT2,
			Titles = StoryText.ACT_TITLES,
		},
	})
end

local function onCutsceneDone(player: Player, id: any)
	local save = StartupDataModule.GetSnapshot(player)
	if type(id) ~= "string" or not save or not Story.AcceptDone(storyState(save), id) then
		return
	end
	if id == "Act1Intro" then
		StartupDataModule.Update(player, function(current)
			current.SeenIntro = true
		end)
	elseif id == "Act1End" then
		local start = Story.Act2Start(save.Valuation, GameConfig.ACT2.ValuationStep)
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.Act1EndSeen = true
			current.Act = start.Act
			current.ActDeploys = start.ActDeploys
			current.ActGoal = start.ActGoal
		end)
		-- The client is still on black from the end of Act1End, so the office swap is never seen.
		PlotService.RebuildUnit(player, 2)
		sendNextBeat(player)
	elseif id == "Act2Intro" then
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.Act2IntroSeen = true
		end)
	end
end

local function onDeployed(player: Player, _payout: number)
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end
	if save.Act == 1 then
		local index = math.clamp(save.DeploysShipped, 1, #StoryText.SIBLING_TEXTS)
		beat(player, "SiblingText", StoryText.SIBLING_TEXTS[index])
	elseif Story.ActGoalReached(save.Act, save.Valuation, save.ActGoal) and not save.StoryFlags.Act2Complete then
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.Act2Complete = true
		end)
		beat(player, "Act2Complete", nil)
	end
end

local function onSibling(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save or save.RentPaid then
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
	sendNextBeat(player)
end

function ProgressService.Init() end

function ProgressService.Start()
	StartupDataModule.OnPlayerLoaded(sendNextBeat)
	AssemblyService.OnDeployed(onDeployed)
	PlotService.OnPromptTriggered("Sibling", onSibling)
	RemoteManager.Listen(RemoteNames.CutsceneDone, onCutsceneDone, 2, 1)
end

return ProgressService
