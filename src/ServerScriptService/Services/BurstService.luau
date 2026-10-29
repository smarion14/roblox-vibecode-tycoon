--!strict
-- Station typing bursts. The server issues each prompt, times it on its own clock and judges the result.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PromptBank = require(Shared:WaitForChild("PromptBank"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local TypingJudge = require(Shared:WaitForChild("TypingJudge"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

type ActiveBurst = {
	Component: string,
	Texts: { string },
	Prompts: { TypingJudge.IssuedPrompt },
	Submissions: { [number]: TypingJudge.Submission },
	Current: number,
	StartedAt: number,
	Rules: TypingJudge.BurstRules,
	Preview: boolean,
	Finished: boolean,
}

local BurstService = {}

local bursts: { [Player]: ActiveBurst } = {}
local rng = Random.new()

local function pickPrompts(component: string, count: number): { string }
	local pool = table.clone(PromptBank.BURST_PROMPTS[component])
	local picked: { string } = {}
	for _ = 1, math.min(count, #pool) do
		table.insert(picked, table.remove(pool, rng:NextInteger(1, #pool)) :: string)
	end
	return picked
end

local function issue(player: Player, burst: ActiveBurst, index: number)
	local now = os.clock()
	burst.Current = index
	burst.Prompts[index] = { Text = burst.Texts[index], IssuedAt = now }
	local nextText = if burst.Preview then burst.Texts[index + 1] else nil
	local timeLeft = burst.Rules.TimeLimit - (now - burst.StartedAt)
	RemoteManager.FireClient(RemoteNames.BurstPrompt, player, index, burst.Texts[index], nextText, timeLeft)
end

local function finish(player: Player, burst: ActiveBurst)
	if burst.Finished or bursts[player] ~= burst then
		return
	end
	burst.Finished = true
	bursts[player] = nil

	-- Prompts never reached still count against the burst.
	for index = 1, #burst.Texts do
		if not burst.Prompts[index] then
			burst.Prompts[index] = { Text = burst.Texts[index], IssuedAt = burst.StartedAt }
		end
	end

	local result = TypingJudge.JudgeBurst(burst.Prompts, burst.Submissions, burst.Rules)
	local grade: TypingJudge.Grade = if result.Flagged then "C" else result.Grade
	StartupDataModule.Update(player, function(save)
		save.Inventory = Economy.AddUnit(save.Inventory, burst.Component, grade)
	end)
	StartupDataModule.SetActivity(player, "Idle")
	RemoteManager.FireClient(RemoteNames.BurstFinished, player, grade, result.Accuracy)
end

local function onStation(player: Player, part: BasePart)
	local component = part:GetAttribute("Component")
	if type(component) ~= "string" or not PromptBank.BURST_PROMPTS[component] then
		return
	end
	local save = StartupDataModule.GetSnapshot(player)
	if not save or StartupDataModule.GetActivity(player) ~= "Idle" then
		return
	end
	if not AssemblyService.GetActiveJob(player) then
		RemoteManager.FireClient(RemoteNames.Notice, player, "Pick up a job on your phone first.")
		return
	end

	local rules, preview = Economy.ApplyGear(GameConfig.BURST_RULES, save.Gear, GameConfig.GEAR)
	local burst: ActiveBurst = {
		Component = component,
		Texts = pickPrompts(component, GameConfig.BURST_PROMPT_COUNT),
		Prompts = {},
		Submissions = {},
		Current = 1,
		StartedAt = os.clock(),
		Rules = rules,
		Preview = preview,
		Finished = false,
	}
	bursts[player] = burst
	StartupDataModule.SetActivity(player, "Burst")
	issue(player, burst, 1)
	task.delay(rules.TimeLimit + rules.LatencyGrace, finish, player, burst)
end

local function onSubmit(player: Player, index: any, text: any)
	if type(index) ~= "number" or type(text) ~= "string" or #text > GameConfig.MAX_REMOTE_STRING then
		return
	end
	local burst = bursts[player]
	if not burst or burst.Finished or index ~= burst.Current or burst.Submissions[index] then
		return
	end

	burst.Submissions[index] = { Text = text, ReceivedAt = os.clock() }
	if index < #burst.Texts then
		issue(player, burst, index + 1)
	else
		finish(player, burst)
	end
end

function BurstService.Init() end

function BurstService.Start()
	PlotService.OnPromptTriggered("Station", onStation)
	RemoteManager.Listen(RemoteNames.SubmitBurstPrompt, onSubmit)
	-- Leaving mid-burst discards it: nothing is added and the activity lock dies with the session.
	Players.PlayerRemoving:Connect(function(player: Player)
		bursts[player] = nil
	end)
end

return BurstService
