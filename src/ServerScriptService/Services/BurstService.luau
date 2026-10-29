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

local WATCH_SECONDS = 0.1

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

local function deadlineOf(burst: ActiveBurst): number
	return TypingJudge.BurstDeadline(burst.Prompts, burst.Submissions, burst.Rules)
end

-- timeDelta is how much the last judged prompt moved the countdown, so the client can show "+6s" or "-1.5s".
local function issue(player: Player, burst: ActiveBurst, index: number, timeDelta: number)
	local now = os.clock()
	burst.Current = index
	burst.Prompts[index] = { Text = burst.Texts[index], IssuedAt = now }
	local nextText = if burst.Preview then burst.Texts[index + 1] else nil
	local timeLeft = deadlineOf(burst) - now
	RemoteManager.FireClient(RemoteNames.BurstPrompt, player, index, burst.Texts[index], nextText, timeLeft, timeDelta)
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
	issue(player, burst, 1, 0)

	-- The deadline moves as prompts are judged, so watch it instead of a fixed delay.
	task.spawn(function()
		while not burst.Finished and bursts[player] == burst do
			if os.clock() > deadlineOf(burst) + rules.LatencyGrace then
				finish(player, burst)
				break
			end
			task.wait(WATCH_SECONDS)
		end
	end)
end

local function onSubmit(player: Player, index: any, text: any)
	-- Blank input (a stray Enter) is ignored; oversize text is cut and judged rather than dropped.
	if type(index) ~= "number" or type(text) ~= "string" or string.match(text, "^%s*$") then
		return
	end
	text = string.sub(text, 1, GameConfig.MAX_REMOTE_STRING)
	local burst = bursts[player]
	if not burst or burst.Finished or index ~= burst.Current or burst.Submissions[index] then
		return
	end

	local before = deadlineOf(burst)
	burst.Submissions[index] = { Text = text, ReceivedAt = os.clock() }
	if index < #burst.Texts then
		issue(player, burst, index + 1, deadlineOf(burst) - before)
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
