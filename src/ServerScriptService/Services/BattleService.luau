--!strict
-- Deploy battles. The server owns the simulation on its own clock; clients only animate and send raw input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleState = require(Shared:WaitForChild("BattleState"))
local BulletHell = require(Shared:WaitForChild("BulletHell"))
local Economy = require(Shared:WaitForChild("Economy"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PromptBank = require(Shared:WaitForChild("PromptBank"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local IncidentService = require(script.Parent:WaitForChild("IncidentService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

type ActiveBattle = {
	Battle: BattleState.Battle,
	LastKey: string,
	Running: boolean,
	SentBugs: number, -- bugs the client has definitions for; shards appended later go out in BattleUpdate.Spawned
}

-- Act 3 bullet hell. Its clock is os.clock() - ClockStart, so the battle starts at 0 on the server just as it does on
-- the client (BulletHell.New(0, ...) on both sides gives bit-identical schedules).
-- ShipLag: ship samples reach the server about half a round trip after the client drew them, so they're stamped that
-- much earlier (half the ping at battle start, capped). The cap stays well under LatencyGrace, so a stamp never lands
-- on a step that's already judged, and a cheater faking lag gains at most SHIP_LAG_CAP of hindsight.
type HellBattle = {
	Battle: BulletHell.Battle,
	ClockStart: number,
	ShipLag: number,
	LastKey: string,
	SentKills: { [number]: boolean },
	Running: boolean,
}

local TICK_SECONDS = 0.1
-- above the ship plus every wingman (a beam reports up to 4 at once); BattleState also enforces per-weapon budgets
local SHOT_RATE_LIMIT = 30
local SHIP_RATE_LIMIT = 15 -- the client streams its ship at 10 Hz
local WEAPONS: { [string]: BattleState.Weapon } = { Ship = "Ship", Spread = "Spread", Beam = "Beam", Missile = "Missile" }
local BOSSES: { [string]: BulletHell.BossKind } = { Hacker = "Hacker", Naysayer = "Naysayer", Swarm = "Swarm" }
local SHIP_LAG_CAP = 0.1

local BattleService = {}

local battles: { [Player]: ActiveBattle } = {}
local hells: { [Player]: HellBattle } = {}

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
	local score = Economy.PerformanceScore(result.MoodRatio, result.Accuracy, result.MaxCombo)
	local payout = AssemblyService.SettleDeploy(player, result.Status == "Shipped", score)
	StartupDataModule.SetActivity(player, "Idle")
	RemoteManager.FireClient(RemoteNames.BattleEnded, player, result, payout, Economy.PerformanceGrade(score))
end

-- force: only for accepted input, so a client spamming invalid claims can't pull a snapshot per call.
local function afterInput(player: Player, active: ActiveBattle, force: boolean)
	pushUpdate(player, active, force)
	if active.Battle.Status ~= "Running" then
		endBattle(player, active)
	end
end

local function hellNow(active: HellBattle): number
	return os.clock() - active.ClockStart
end

-- Pushes lives, grazes, combo, invulnerability, the shield, boss HP and new kills (id + time, so the client cancels
-- the same bullets) whenever any of it changed. Times are already relative to the battle start.
local function pushHellUpdate(player: Player, active: HellBattle)
	local b = active.Battle
	local bosses = {}
	local bossHp = 0
	local killed = {}
	for _, enemy in b.Enemies do
		if enemy.Kind ~= "Popcorn" then
			table.insert(bosses, { Id = enemy.Id, Hp = enemy.Hp })
			bossHp += enemy.Hp
		end
		local killedAt = enemy.KilledAt
		if killedAt and not active.SentKills[enemy.Id] then
			active.SentKills[enemy.Id] = true
			table.insert(killed, { Id = enemy.Id, At = killedAt })
		end
	end
	local key = `{b.Lives}|{b.Grazes}|{b.Combo}|{b.InvulnUntil}|{b.ShieldUsedPhase}|{bossHp}|{b.SplitAt}|{b.BossDownAt}|{b.Status}`
	if #killed == 0 and key == active.LastKey then
		return
	end
	active.LastKey = key
	RemoteManager.FireClient(RemoteNames.BattleUpdate, player, {
		Lives = b.Lives,
		Grazes = b.Grazes,
		Combo = b.Combo,
		InvulnUntil = b.InvulnUntil,
		ShieldUsedPhase = b.ShieldUsedPhase,
		Bosses = bosses,
		Killed = killed,
		SplitAt = b.SplitAt,
		BossDownAt = b.BossDownAt,
		Status = b.Status,
	})
end

-- Failed pays nothing and keeps the job (SettleDeploy); the Act 3 reputation multiplier is applied in there.
local function endHell(player: Player, active: HellBattle)
	if not active.Running then
		return
	end
	active.Running = false
	hells[player] = nil

	local b = active.Battle
	local result = BulletHell.Result(b)
	local payout = AssemblyService.SettleDeploy(player, result.Status == "Shipped", result.Score)
	StartupDataModule.SetActivity(player, "Idle")
	RemoteManager.FireClient(RemoteNames.BattleEnded, player, {
		Status = result.Status,
		Successes = b.Killed,
		Mistakes = b.MaxLives - result.LivesLeft,
		MaxCombo = result.MaxCombo,
		Grazes = result.Grazes,
	}, payout, Economy.PerformanceGrade(result.Score))
end

local function afterHellInput(player: Player, active: HellBattle)
	pushHellUpdate(player, active)
	if active.Battle.Status ~= "Running" then
		endHell(player, active)
	end
end

local function hiredRoles(hires: { [string]: boolean }): { string }
	local roles: { string } = {}
	for _, role in GameConfig.COMPONENTS do
		if hires[role] then
			table.insert(roles, role)
		end
	end
	return roles
end

-- Act 3: a seeded bullet hell. The client gets the seed and the options and rebuilds the same schedule.
local function startBulletHell(player: Player, inventory: Economy.Inventory, hires: { [string]: boolean }, job: GameConfig.ClientDef)
	local parts = BattleState.LoadoutFrom(inventory, GameConfig.BATTLE_RULES)
	local options: BulletHell.Options = {
		Boss = BOSSES[job.Boss or ""] or "Hacker",
		EliteHalfWaves = IncidentService.TakeEliteWave(player),
		Loadout = { Shield = parts.Shield > 0, ExtraLife = parts.Rollback, Homing = parts.Homing, FireInterval = parts.FireInterval },
		Wingmen = hiredRoles(hires),
	}
	local seed = Random.new():NextInteger(1, 2 ^ 31 - 1)
	local active: HellBattle = {
		Battle = BulletHell.New(0, seed, options, GameConfig.BULLET_HELL),
		ClockStart = os.clock(),
		ShipLag = math.clamp(player:GetNetworkPing() / 2, 0, SHIP_LAG_CAP),
		LastKey = "",
		SentKills = {},
		Running = true,
	}
	local serverStart = Workspace:GetServerTimeNow()
	hells[player] = active
	StartupDataModule.SetActivity(player, "Battle")
	RemoteManager.FireClient(RemoteNames.BattleStarted, player, {
		Mode = "BulletHell",
		ServerStart = serverStart,
		ClientName = job.Name,
		Seed = seed,
		Boss = options.Boss,
		EliteHalfWaves = options.EliteHalfWaves,
		Loadout = options.Loadout,
		Wingmen = options.Wingmen,
	})

	-- Tick judges up to LatencyGrace behind the clock on a fixed grid, so this cadence only sets update latency.
	task.spawn(function()
		while active.Running and hells[player] == active do
			task.wait(TICK_SECONDS)
			if not active.Running then
				break
			end
			BulletHell.Tick(active.Battle, hellNow(active))
			afterHellInput(player, active)
		end
	end)
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
	if save.Act == 3 then
		startBulletHell(player, save.Inventory, save.Hires, job)
		return
	end

	-- Act 2 is a squad battle: hired roles fly as wingmen (in role order), the job's project picks the extra
	-- enemy, and the boss fires volleys. Act 1 passes no options and plays exactly as before.
	local options: BattleState.SquadOptions? = nil
	if save.Act == 2 then
		local wingmen = hiredRoles(save.Hires)
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
	local hell = hells[player]
	if hell then
		if hell.Running then
			BulletHell.Kill(hell.Battle, bugId, hellNow(hell), chosen)
			afterHellInput(player, hell)
		end
		return
	end
	local active = battles[player]
	if not active or not active.Running then
		return
	end
	local killed = BattleState.Kill(active.Battle, bugId, os.clock(), chosen)
	afterInput(player, active, killed)
end

local function isUnit(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 1 -- NaN fails ==, the range rejects infinity
end

-- The client streams its ship x (0-1 across the field), plus y in Act 3; the battle clamps it to what the ship could
-- have flown, on the server clock.
local function onShipMoved(player: Player, x: any, y: any)
	if not isUnit(x) then
		return
	end
	local hell = hells[player]
	if hell then
		if hell.Running and isUnit(y) then
			BulletHell.MoveShip(hell.Battle, x, y, math.max(hellNow(hell) - hell.ShipLag, 0))
		end
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
		local hell = hells[player]
		if hell then
			hell.Running = false
			hells[player] = nil
		end
	end)
end

return BattleService
