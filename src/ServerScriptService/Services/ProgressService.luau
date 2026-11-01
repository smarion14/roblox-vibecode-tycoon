--!strict
-- Story flow: Story.NextBeat picks the cutscene a save still owes, the client plays it and reports CutsceneDone.
-- Finishing the Act 1 ending moves the player into Act 2 and their office; finishing the Act 2 ending moves them into
-- Act 3 and the campus. Sibling texts after deploys, paying rent ends Act 1, reaching the valuation goal ends Act 2,
-- earning the Act 3 goal in deploy payouts sends the finale. The startup sign replays the finale after that.
local Players = game:GetService("Players")
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
local StartupNameService = require(script.Parent:WaitForChild("StartupNameService"))

local REPLAY_PAUSE_SECONDS = 90

local ProgressService = {}

-- Players watching the finale replay, to the os.clock() time the pause gives up waiting for its CutsceneDone.
local replayingUntil: { [Player]: number } = {}

local function beat(player: Player, kind: string, payload: any)
	RemoteManager.FireClient(RemoteNames.StoryBeat, player, kind, payload)
end

local function storyState(save: StartupDataModule.PlayerSave): Story.StoryState
	return { Act = save.Act, SeenIntro = save.SeenIntro, RentPaid = save.RentPaid, Flags = save.StoryFlags }
end

-- Sends a cutscene with the copy and numbers every script reads (Cutscenes.Copy).
local function sendCutscene(player: Player, save: StartupDataModule.PlayerSave, id: string, replay: boolean)
	beat(player, "Cutscene", {
		Id = id,
		Replay = replay,
		Copy = {
			RentGoal = GameConfig.RENT_GOAL,
			ActGoal = save.ActGoal,
			Act1Intro = StoryText.ACT1_INTRO,
			Act1End = StoryText.ACT1_END,
			Act2Text = StoryText.ACT2_INTRO_TEXT,
			BrotherText = StoryText.BROTHER_TEXT_ACT2,
			Titles = StoryText.ACT_TITLES,
			Act3Goal = GameConfig.ACT3.Goal,
			StartupName = save.StartupName or PlotService.UNTITLED_NAME,
			PlayerName = player.DisplayName,
			Act2Ticker = StoryText.ACT2_END_TICKER,
			Act3Text = StoryText.ACT3_INTRO_TEXT,
			BrotherTextAct3 = StoryText.BROTHER_TEXT_ACT3,
			Finale = StoryText.FINALE,
		},
	})
end

-- Sends the cutscene this save still owes, if any.
local function sendNextBeat(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end
	local id = Story.NextBeat(storyState(save))
	if id then
		sendCutscene(player, save, id, false)
	end
end

-- The startup sign's "Replay ending": the finale again, flagged Replay. Its CutsceneDone changes nothing, because
-- AcceptDone only takes the scene NextBeat owes, and nothing is owed once the finale has been seen.
local function onReplayEnding(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save or not save.StoryFlags.GameComplete or StartupDataModule.GetActivity(player) ~= "Idle" then
		return
	end
	if Story.NextBeat(storyState(save)) == nil then
		replayingUntil[player] = os.clock() + REPLAY_PAUSE_SECONDS
		sendCutscene(player, save, "Finale", true)
	end
end

-- IncidentService pauses incidents while this is true.
function ProgressService.IsReplaying(player: Player): boolean
	local untilTime = replayingUntil[player]
	if untilTime and os.clock() >= untilTime then
		replayingUntil[player] = nil
		return false
	end
	return untilTime ~= nil
end

local function onCutsceneDone(player: Player, id: any)
	if id == "Finale" then
		replayingUntil[player] = nil -- the replay is over even though AcceptDone below rejects it
	end
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
		local firstTime = not save.StoryFlags.Act2TutorialSeen
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.Act2IntroSeen = true
			current.StoryFlags.Act2TutorialSeen = true
		end)
		if firstTime then
			beat(player, "Act2Tutorial", nil)
		end
	elseif id == "Act2End" then
		local start = Story.Act3Start(GameConfig.ACT3.StartReputation)
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.Act2EndSeen = true
			current.Act = start.Act
			current.ActDeploys = start.ActDeploys
			current.Reputation = start.Reputation
			current.Act3Earned = start.Act3Earned
		end)
		-- Act2End ends on black, so the campus swap is never seen. No incident can be open: they only run in Act 3.
		PlotService.RebuildUnit(player, 3)
		sendNextBeat(player)
	elseif id == "Act3Intro" then
		-- IncidentService starts this player's schedule once nothing is owed, so the first incident lands MinGap..MaxGap later.
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.Act3IntroSeen = true
		end)
	elseif id == "Finale" then
		-- IncidentService restarts the schedule at the free-play rate once FinaleSeen is set.
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.FinaleSeen = true
		end)
	end
end

-- Celebrates each milestone of the save's act once: flags it in the save, then sends its card.
function ProgressService.CheckMilestones(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end
	local act3 = save.Act == 3
	local defs: { GameConfig.Milestone } = if act3 then GameConfig.ACT3.Milestones else GameConfig.ACT2.Milestones
	-- Act 3's hire milestone counts key hires; Act 2's counts component hires.
	local hires = 0
	for id in save.Hires do
		if (GameConfig.KEY_HIRES[id] ~= nil) == act3 then
			hires += 1
		end
	end
	local state: Story.MilestoneState = {
		Act = save.Act,
		ActDeploys = save.ActDeploys,
		Valuation = save.Valuation,
		ActGoal = save.ActGoal,
		Hires = hires,
		Act3Earned = save.Act3Earned,
		Act3Goal = GameConfig.ACT3.Goal,
		Flags = save.StoryFlags,
	}
	local reached = Story.NewMilestones(defs :: any, state, GameConfig.ACT2.ValuationStep)
	if #reached == 0 then
		return
	end
	StartupDataModule.Update(player, function(current)
		for _, id in reached do
			current.StoryFlags[`Milestone_{id}`] = true
		end
	end)
	for _, milestone in defs do
		if table.find(reached, milestone.Id) then
			beat(player, "Milestone", { Title = milestone.Title, Body = milestone.Body })
		end
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
	else
		ProgressService.CheckMilestones(player)
	end
	if save.Act == 2 and Story.ActGoalReached(save.Act, save.Valuation, save.ActGoal) and not save.StoryFlags.Act2Complete then
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.Act2Complete = true
		end)
		sendNextBeat(player) -- Act2End
	elseif save.Act == 3 and save.Act3Earned >= GameConfig.ACT3.Goal and not save.StoryFlags.GameComplete then
		StartupDataModule.Update(player, function(current)
			current.StoryFlags.GameComplete = true
		end)
		StartupNameService.RefreshReplayPrompt(player)
		sendNextBeat(player) -- Finale
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
	StartupNameService.OnReplayEnding(onReplayEnding)
	Players.PlayerRemoving:Connect(function(player: Player)
		replayingUntil[player] = nil
	end)
end

return ProgressService
