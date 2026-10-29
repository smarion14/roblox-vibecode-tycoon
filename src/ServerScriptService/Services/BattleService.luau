--!strict
-- Deploy battles. The server owns the simulation on its own clock; clients only animate and send raw input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleState = require(Shared:WaitForChild("BattleState"))
local Economy = require(Shared:WaitForChild("Economy"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PromptBank = require(Shared:WaitForChild("PromptBank"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local TypingJudge = require(Shared:WaitForChild("TypingJudge"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

type ActiveBattle = {
	Battle: BattleState.Battle,
	LastKey: string,
	Running: boolean,
}

local TICK_SECONDS = 0.1
local PROMPT_RATE_LIMIT = 5
local SQUASH_RATE_LIMIT = 15
local JUDGE: BattleState.Judge = { Accuracy = TypingJudge.Accuracy, IsPlausible = TypingJudge.IsPlausible }

local BattleService = {}

local battles: { [Player]: ActiveBattle } = {}

local function shuffled(list: { string }, rng: Random): { string }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function snapshotKey(snapshot: BattleState.BattleSnapshot): string
	local resolved = 0
	for _, state in snapshot.BugStates do
		if state ~= "Pending" then
			resolved += 1
		end
	end
	return `{snapshot.Mood}|{snapshot.Combo}|{snapshot.Progress}|{snapshot.PromptText}|{snapshot.Status}|{resolved}`
end

local function pushUpdate(player: Player, active: ActiveBattle, force: boolean)
	local snapshot = BattleState.Snapshot(active.Battle)
	local key = snapshotKey(snapshot)
	if force or key ~= active.LastKey then
		active.LastKey = key
		RemoteManager.FireClient(RemoteNames.BattleUpdate, player, snapshot)
	end
end

local function endBattle(player: Player, active: ActiveBattle)
	if not active.Running then
		return
	end
	active.Running = false
	battles[player] = nil

	local result = BattleState.Result(active.Battle)
	local payout = AssemblyService.SettleDeploy(player, result)
	StartupDataModule.SetActivity(player, "Idle")
	RemoteManager.FireClient(RemoteNames.BattleEnded, player, result, payout)
end

local function afterInput(player: Player, active: ActiveBattle)
	pushUpdate(player, active, true)
	if active.Battle.Status ~= "Running" then
		endBattle(player, active)
	end
end

local function missingComponents(inventory: Economy.Inventory, recipe: Economy.Recipe): { string }
	local missing: { string } = {}
	for _, component in GameConfig.COMPONENTS do
		local grades = inventory[component]
		local have = if grades then grades.S + grades.A + grades.B + grades.C else 0
		local need = recipe[component] or 0
		if have < need then
			table.insert(missing, `{GameConfig.STATION_NAMES[component]} {have}/{need}`)
		end
	end
	return missing
end

local function onDeployTerminal(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save or StartupDataModule.GetActivity(player) ~= "Idle" then
		return
	end
	local job = AssemblyService.GetActiveJob(player)
	if not job then
		RemoteManager.FireClient(RemoteNames.Notice, player, "Pick up a job on your phone first.")
		return
	end
	local recipe = GameConfig.RECIPES[job.Project]
	if not Economy.MeetsRecipe(save.Inventory, recipe) then
		local missing = table.concat(missingComponents(save.Inventory, recipe), ", ")
		RemoteManager.FireClient(RemoteNames.Notice, player, `Not ready to ship. Missing: {missing}`)
		return
	end

	local rng = Random.new()
	local clockStart = os.clock()
	local serverStart = Workspace:GetServerTimeNow()
	local battle = BattleState.New(
		clockStart,
		Economy.AverageQuality(save.Inventory),
		shuffled(PromptBank.BATTLE_PROMPTS, rng),
		PromptBank.BUG_WORDS,
		GameConfig.BATTLE_RULES,
		function(): number
			return rng:NextNumber()
		end
	)

	local bugs = {}
	for _, bug in battle.Bugs do
		table.insert(bugs, {
			Id = bug.Id,
			Word = bug.Word,
			Side = bug.Side,
			SpawnOffset = bug.SpawnAt - clockStart,
			ReachOffset = bug.ReachAt - clockStart,
		})
	end

	local active: ActiveBattle = { Battle = battle, LastKey = "", Running = true }
	battles[player] = active
	StartupDataModule.SetActivity(player, "Battle")
	RemoteManager.FireClient(RemoteNames.BattleStarted, player, {
		ServerStart = serverStart,
		ClientName = job.Name,
		PromptText = battle.Prompts[1],
		Mood = battle.Mood,
		ShipPromptsRequired = GameConfig.BATTLE_RULES.ShipPromptsRequired,
		Bugs = bugs,
	})

	task.spawn(function()
		while active.Running and battles[player] == active do
			task.wait(TICK_SECONDS)
			if not active.Running then
				break
			end
			BattleState.Tick(active.Battle, os.clock())
			pushUpdate(player, active, false)
			if active.Battle.Status ~= "Running" then
				endBattle(player, active)
			end
		end
	end)
end

local function onSubmitPrompt(player: Player, text: any)
	if type(text) ~= "string" then
		return
	end
	-- Oversize text is cut and judged (it scores 0) rather than dropped, so the client is never left waiting.
	text = string.sub(text, 1, GameConfig.MAX_REMOTE_STRING)
	local active = battles[player]
	if not active or not active.Running then
		return
	end
	BattleState.SubmitPrompt(active.Battle, text, os.clock(), JUDGE)
	afterInput(player, active)
end

local function onSquash(player: Player, word: any)
	if type(word) ~= "string" or #word > GameConfig.MAX_REMOTE_STRING then
		return
	end
	local active = battles[player]
	if not active or not active.Running then
		return
	end
	BattleState.Squash(active.Battle, word, os.clock())
	afterInput(player, active)
end

function BattleService.Init() end

function BattleService.Start()
	PlotService.OnPromptTriggered("DeployTerminal", onDeployTerminal)
	RemoteManager.Listen(RemoteNames.BattleSubmitPrompt, onSubmitPrompt, PROMPT_RATE_LIMIT, 1)
	RemoteManager.Listen(RemoteNames.BattleSquash, onSquash, SQUASH_RATE_LIMIT, 1)
	-- Leaving mid-battle settles nothing: the job and every built component are kept.
	Players.PlayerRemoving:Connect(function(player: Player)
		local active = battles[player]
		if active then
			active.Running = false
			battles[player] = nil
		end
	end)
end

return BattleService
