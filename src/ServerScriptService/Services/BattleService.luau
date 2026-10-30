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
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

type ActiveBattle = {
	Battle: BattleState.Battle,
	LastKey: string,
	Running: boolean,
	SentBugs: number, -- bugs the client has definitions for; shards appended later go out in BattleUpdate.Spawned
}

local TICK_SECONDS = 0.1
-- above the ship plus every wingman (a beam reports up to 4 at once); BattleState also enforces per-weapon budgets
local SHOT_RATE_LIMIT = 30
local SHIP_RATE_LIMIT = 15 -- the client streams its ship x at 10 Hz
local WEAPONS: { [string]: BattleState.Weapon } = { Ship = "Ship", Spread = "Spread", Beam = "Beam", Missile = "Missile" }

local BattleService = {}

local battles: { [Player]: ActiveBattle } = {}

local function bulletHits(battle: BattleState.Battle): number
	local hits = 0
	for _, bullet in battle.Bullets do
		if bullet.State == "Hit" then
			hits += 1
		end
	end
	return hits
end

local function snapshotKey(snapshot: BattleState.BattleSnapshot, hits: number): string
	local resolved = 0
	for _, state in snapshot.BugStates do
		if state ~= "Pending" then
			resolved += 1
		end
	end
	return `{snapshot.Mood}|{snapshot.Combo}|{snapshot.BossHp}|{snapshot.Shield}|{snapshot.RollbackUsed}|{snapshot.Status}|{resolved}`
		.. `|{snapshot.BugCount}|{snapshot.SlowUntil}|{snapshot.BossDiedAt}|{snapshot.WingShieldReadyAt}|{hits}`
end

-- A bug's flight plan with times relative to the battle start; the client replays it with BattleState.BugPosition.
local function bugInfo(bug: BattleState.Bug, clockStart: number)
	return {
		Id = bug.Id,
		Kind = bug.Kind,
		Wave = bug.Wave,
		Side = bug.Side,
		SpawnAt = bug.SpawnAt - clockStart,
		EntryTime = bug.EntryTime,
		SpawnX = bug.SpawnX,
		FormX = bug.FormX,
		FormY = bug.FormY,
		DiveAt = bug.DiveAt - clockStart,
		DiveX = bug.DiveX,
		ReachAt = bug.ReachAt - clockStart,
		Hp = bug.Hp,
	}
end

-- Snapshot times go out relative to the battle start, plus the definitions of any bugs born since the last update.
local function pushUpdate(player: Player, active: ActiveBattle, force: boolean)
	local battle = active.Battle
	local snapshot = BattleState.Snapshot(battle)
	local hits = bulletHits(battle)
	local key = snapshotKey(snapshot, hits)
	if not force and key == active.LastKey then
		return
	end
	active.LastKey = key
	local start = battle.StartTime
	local payload: any = table.clone(snapshot)
	payload.SlowUntil = snapshot.SlowUntil - start
	payload.WingShieldReadyAt = snapshot.WingShieldReadyAt - start
	payload.BossDiedAt = if snapshot.BossDiedAt then snapshot.BossDiedAt - start else nil
	payload.BulletHits = hits
	if #battle.Bugs > active.SentBugs then
		local spawned = {}
		for id = active.SentBugs + 1, #battle.Bugs do
			table.insert(spawned, bugInfo(battle.Bugs[id], start))
		end
		payload.Spawned = spawned
		active.SentBugs = #battle.Bugs
	end
	RemoteManager.FireClient(RemoteNames.BattleUpdate, player, payload)
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
	local score = Economy.PerformanceScore(result.MoodRatio, result.Accuracy, result.MaxCombo)
	RemoteManager.FireClient(RemoteNames.BattleEnded, player, result, payout, Economy.PerformanceGrade(score))
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

	-- Act 2 is a squad battle: hired roles fly as wingmen (in role order), the job's project picks the extra
	-- enemy, and the boss fires volleys. Act 1 passes no options and plays exactly as before.
	local options: BattleState.SquadOptions? = nil
	if save.Act == 2 then
		local wingmen: { string } = {}
		for _, role in GameConfig.COMPONENTS do
			if save.Hires[role] then
				table.insert(wingmen, role)
			end
		end
		local enemyKind: ("Crash" | "Lag")? = if job.Project == "MobileApp"
			then "Crash"
			elseif job.Project == "Game" then "Lag"
			else nil
		options = { Wingmen = wingmen, EnemyKind = enemyKind, BossVolleys = true, Squad = GameConfig.SQUAD }
	end

	local rng = Random.new()
	local clockStart = os.clock()
	local serverStart = Workspace:GetServerTimeNow()
	local loadout = BattleState.LoadoutFrom(save.Inventory, GameConfig.BATTLE_RULES)
	local battle = BattleState.New(
		clockStart,
		Economy.AverageQuality(save.Inventory),
		loadout,
		BattleState.RulesForAct(GameConfig.BATTLE_RULES, GameConfig.ACT_BATTLE[save.Act]),
		function(): number
			return rng:NextNumber()
		end,
		options
	)

	-- The client gets every bug's flight plan with times relative to the battle start, and replays the same
	-- BattleState.BugPosition paths against the shared server clock. Boss bullets go out the same way.
	local bugs = {}
	for _, bug in battle.Bugs do
		table.insert(bugs, bugInfo(bug, clockStart))
	end
	local bullets = {}
	for _, bullet in battle.Bullets do
		table.insert(bullets, {
			Id = bullet.Id,
			FiredAt = bullet.FiredAt - clockStart,
			OriginX = bullet.OriginX,
			OriginY = bullet.OriginY,
			DirX = bullet.DirX,
			DirY = bullet.DirY,
		})
	end
	local squad = if options then { Wingmen = options.Wingmen, EnemyKind = options.EnemyKind, Rules = GameConfig.SQUAD } else nil

	local active: ActiveBattle = { Battle = battle, LastKey = "", Running = true, SentBugs = #battle.Bugs }
	battles[player] = active
	StartupDataModule.SetActivity(player, "Battle")
	RemoteManager.FireClient(RemoteNames.BattleStarted, player, {
		ServerStart = serverStart,
		ClientName = job.Name,
		BossName = string.upper(PromptBank.BOSS_PHRASES[rng:NextInteger(1, #PromptBank.BOSS_PHRASES)]),
		Loadout = loadout,
		Mood = battle.Mood,
		WaveCount = #GameConfig.BATTLE_RULES.Waves,
		Bugs = bugs,
		Bullets = bullets,
		Squad = squad,
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

-- A shot hit a bug: the client sends the bug's id and the weapon (nil = the ship); BattleState checks it's possible.
local function onShotHit(player: Player, bugId: any, weapon: any)
	if type(bugId) ~= "number" or bugId % 1 ~= 0 then -- NaN and infinity fail the integer check too
		return
	end
	local chosen: BattleState.Weapon? = nil
	if weapon ~= nil then
		chosen = if type(weapon) == "string" then WEAPONS[weapon] else nil
		if not chosen then
			return
		end
	end
	local active = battles[player]
	if not active or not active.Running then
		return
	end
	BattleState.Kill(active.Battle, bugId, os.clock(), chosen)
	afterInput(player, active)
end

-- The client streams its ship x (0-1 across the field); BattleState clamps it to what the ship could have flown.
local function onShipMoved(player: Player, x: any)
	if type(x) ~= "number" or x ~= x or x < 0 or x > 1 then -- x ~= x rejects NaN, the range rejects infinity
		return
	end
	local active = battles[player]
	if not active or not active.Running then
		return
	end
	BattleState.MoveShip(active.Battle, x, os.clock())
end

function BattleService.Init() end

function BattleService.Start()
	PlotService.OnPromptTriggered("DeployTerminal", onDeployTerminal)
	RemoteManager.Listen(RemoteNames.BattleSquash, onShotHit, SHOT_RATE_LIMIT, 1)
	RemoteManager.Listen(RemoteNames.BattleShip, onShipMoved, SHIP_RATE_LIMIT, 1)
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
