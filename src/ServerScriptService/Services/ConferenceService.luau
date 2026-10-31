--!strict
-- Act 3 conferences (spec §9): the ConferenceStage podium starts a rhythm-typing keynote. The server holds the round,
-- stamps every typed slogan on its own clock, judges it with Keynote and grants reputation. 10-minute cooldown in
-- save.ConferenceReadyAt (os.time).
--
-- Remotes:
--   ConferenceStart({ Slogans = { { Text, OpenAt, CloseAt } }, StartedAt, Podium })
--     OpenAt/CloseAt: seconds after StartedAt (a Workspace:GetServerTimeNow() timestamp). Podium: the stage's BasePart.
--   ConferenceAction(text)   one call per typed slogan. The server stamps At = server clock - StartedAt and files it
--     under the slogan whose window holds At (Keynote.WindowAt); text between beats, or for a slogan already
--     answered, is dropped. The round ends when every slogan is answered or its last window has passed.
--   ConferenceResult(grade, repDelta, newRep, multiplier)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Keynote = require(Shared:WaitForChild("Keynote"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local Reputation = require(Shared:WaitForChild("Reputation"))
local StoryText = require(Shared:WaitForChild("StoryText"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))

type Performance = {
	Round: Keynote.Round,
	StartedAt: number,
	EndsAt: number,
	Submissions: { [number]: Keynote.Submission },
	Count: number,
	Finished: boolean,
}

local COOLDOWN_SECONDS = 600
local END_SLACK = 0.5
local WATCH_SECONDS = 0.2
local ACTION_RATE_LIMIT = 10
-- Behind the podium, facing the audience (podium-local +Z); the root sits ~3 studs above the stage floor.
local SPEAKER_OFFSET = CFrame.new(0, 1.2, -1.6) * CFrame.Angles(0, math.pi, 0)

local ConferenceService = {}

local performances: { [Player]: Performance } = {}
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function nextNumber(): number
	return rng:NextNumber()
end

local function finish(player: Player, performance: Performance)
	if performance.Finished or performances[player] ~= performance then
		return
	end
	performance.Finished = true
	performances[player] = nil

	local result = Keynote.Judge(performance.Round, performance.Submissions)
	local repDelta = Keynote.RepFor(result.Grade)
	local newRep = 0
	StartupDataModule.Update(player, function(current)
		current.Reputation = Reputation.Apply(current.Reputation, repDelta)
		current.StoryFlags.ConferenceGiven = true
		current.ConferenceReadyAt = os.time() + COOLDOWN_SECONDS
		newRep = current.Reputation
	end)
	StartupDataModule.SetActivity(player, "Idle")
	local multiplier = Reputation.Multiplier(newRep, GameConfig.ACT3.MinMultiplier, GameConfig.ACT3.MaxMultiplier)
	RemoteManager.FireClient(RemoteNames.ConferenceResult, player, result.Grade, repDelta, newRep, multiplier)
	ProgressService.CheckMilestones(player)
end

local function onStage(player: Player, podium: BasePart)
	local save = StartupDataModule.GetSnapshot(player)
	if not save or save.Act < 3 or performances[player] or StartupDataModule.GetActivity(player) ~= "Idle" then
		return
	end
	local left = math.ceil(save.ConferenceReadyAt - os.time())
	if left > 0 then
		RemoteManager.FireClient(RemoteNames.Notice, player, string.format("Next conference in %d:%02d", left // 60, left % 60))
		return
	end

	local round = Keynote.New(nextNumber, StoryText.KEYNOTE_SLOGANS)
	local startedAt = now()
	local performance: Performance = {
		Round = round,
		StartedAt = startedAt,
		EndsAt = startedAt + round.Slogans[#round.Slogans].CloseAt + Keynote.LATE_GRACE + END_SLACK,
		Submissions = {},
		Count = 0,
		Finished = false,
	}
	performances[player] = performance
	-- The cooldown starts on stage too, so leaving mid-keynote can't reroll a bad one.
	StartupDataModule.Update(player, function(current)
		current.ConferenceReadyAt = os.time() + COOLDOWN_SECONDS
	end)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 and not humanoid.Sit then
		character:PivotTo(podium.CFrame * SPEAKER_OFFSET)
	end
	StartupDataModule.SetActivity(player, "Burst")
	RemoteManager.FireClient(RemoteNames.ConferenceStart, player, {
		Slogans = round.Slogans,
		StartedAt = startedAt,
		Podium = podium,
	})
	task.spawn(function()
		while not performance.Finished do
			task.wait(WATCH_SECONDS)
			if now() > performance.EndsAt then
				finish(player, performance)
			end
		end
	end)
end

local function onAction(player: Player, text: any)
	local performance = performances[player]
	if not performance or performance.Finished then
		return
	end
	if type(text) ~= "string" or #text > GameConfig.MAX_REMOTE_STRING then
		return
	end
	local at = now() - performance.StartedAt
	local index = Keynote.WindowAt(performance.Round, at)
	if not index or performance.Submissions[index] then
		return
	end
	performance.Submissions[index] = { Text = text, At = at }
	performance.Count += 1
	if performance.Count >= #performance.Round.Slogans then
		finish(player, performance)
	end
end

function ConferenceService.Init() end

function ConferenceService.Start()
	PlotService.OnPromptTriggered("ConferenceStage", onStage)
	RemoteManager.Listen(RemoteNames.ConferenceAction, onAction, ACTION_RATE_LIMIT, 1)
	Players.PlayerRemoving:Connect(function(player: Player)
		local performance = performances[player]
		if performance then
			performance.Finished = true
		end
		performances[player] = nil
	end)
end

return ConferenceService
