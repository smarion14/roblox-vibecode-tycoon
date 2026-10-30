--!strict
local BattleState = require("../src/ReplicatedStorage/Shared/BattleState")
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")

local RULES = GameConfig.BATTLE_RULES

local function makeRng(): () -> number
	local n = 0
	return function(): number
		n += 1
		return (n * 0.37) % 1
	end
end

local function grades(s: number, a: number, b: number, c: number): BattleState.GradeCounts
	return { S = s, A = a, B = b, C = c }
end

local BARE: BattleState.Loadout = { Shield = 0, FireInterval = RULES.BaseFireInterval, Rollback = false, Homing = false }

local function newBattle(avgQuality: number, loadout: BattleState.Loadout?): BattleState.Battle
	return BattleState.New(0, avgQuality, loadout or BARE, RULES, makeRng())
end

local function minions(b: BattleState.Battle): { BattleState.Bug }
	local list: { BattleState.Bug } = {}
	for _, bug in b.Bugs do
		if bug.Kind == "Minion" then
			table.insert(list, bug)
		end
	end
	return list
end

local function boss(b: BattleState.Battle): BattleState.Bug
	for _, bug in b.Bugs do
		if bug.Kind == "Boss" then
			return bug
		end
	end
	error("no boss")
end

-- Kills every minion right after it becomes visible, in time order.
local function clearMinionsUntil(b: BattleState.Battle, untilTime: number)
	local list = minions(b)
	table.sort(list, function(x: BattleState.Bug, y: BattleState.Bug): boolean
		return x.SpawnAt < y.SpawnAt
	end)
	for _, bug in list do
		local at = bug.SpawnAt + RULES.VisibleDelay + 0.1
		if at < untilTime then
			BattleState.Kill(b, bug.Id, at)
		end
	end
end

local tests = {}

tests["start mood from quality"] = function()
	assert(newBattle(0).Mood == 70)
	assert(newBattle(3).Mood == 100)
end

tests["waves then one boss"] = function()
	local b = newBattle(3)
	assert(#minions(b) >= RULES.Waves[1].Count + RULES.Waves[2].Count)
	local theBoss = boss(b)
	assert(theBoss.Hp == RULES.BossHp)
	for _, bug in minions(b) do
		assert(bug.SpawnAt < bug.DiveAt and bug.DiveAt < bug.ReachAt, "bug timeline out of order")
		if bug.Wave <= #RULES.Waves then
			assert(bug.SpawnAt < theBoss.SpawnAt)
		end
	end
end

tests["sloppy components bring more bugs"] = function()
	assert(#minions(newBattle(0)) > #minions(newBattle(3)))
end

tests["bug flight path"] = function()
	local b = newBattle(3)
	local bug = minions(b)[1]
	local _, startY = BattleState.BugPosition(bug, bug.SpawnAt)
	assert(startY < 0, "bugs enter from above the screen")
	local formX, formY = BattleState.BugPosition(bug, bug.SpawnAt + bug.EntryTime + 0.01)
	assert(math.abs(formY - bug.FormY) < 1e-6 and formX > 0 and formX < 1)
	local _, endY = BattleState.BugPosition(bug, bug.ReachAt)
	assert(endY > 1, "divers end below your code")
	for t = bug.SpawnAt, bug.ReachAt, 0.25 do
		local x, y = BattleState.BugPosition(bug, t)
		assert(x > -0.2 and x < 1.2 and y > -0.3 and y < 1.2, `off the field at {t}`)
	end
end

tests["bug that reaches your code hurts"] = function()
	local b = newBattle(0)
	local bug = minions(b)[1]
	BattleState.Tick(b, bug.ReachAt + RULES.LatencyGrace - 0.01)
	assert(bug.State == "Pending")
	BattleState.Tick(b, bug.ReachAt + RULES.LatencyGrace + 0.01)
	assert(bug.State == "Hit" and b.Mood == 70 - RULES.MoodHitPenalty and b.Mistakes == 1)
end

tests["shield absorbs hits"] = function()
	local b = newBattle(0, { Shield = 1, FireInterval = RULES.BaseFireInterval, Rollback = false, Homing = false })
	local list = minions(b)
	table.sort(list, function(x: BattleState.Bug, y: BattleState.Bug): boolean
		return x.ReachAt < y.ReachAt
	end)
	BattleState.Tick(b, list[1].ReachAt + RULES.LatencyGrace + 0.01)
	assert(b.Mood == 70 and b.Shield == 0, "the shield should take the first hit")
	BattleState.Tick(b, list[2].ReachAt + RULES.LatencyGrace + 0.01)
	assert(b.Mood == 70 - RULES.MoodHitPenalty)
end

tests["rollback saves you once"] = function()
	local b = newBattle(0, { Shield = 0, FireInterval = RULES.BaseFireInterval, Rollback = true, Homing = false })
	b.Mood = 10
	local bug = minions(b)[1]
	BattleState.Tick(b, bug.ReachAt + RULES.LatencyGrace + 0.01)
	assert(b.Mood == RULES.RollbackMood and b.RollbackUsed and b.Status == "Running")
end

tests["kill a visible bug"] = function()
	local b = newBattle(0)
	local bug = minions(b)[1]
	assert(BattleState.Kill(b, bug.Id, bug.SpawnAt + 0.05) == false, "can't hit a bug that isn't on screen yet")
	assert(BattleState.Kill(b, bug.Id, bug.SpawnAt + RULES.VisibleDelay + 0.1) == true)
	assert(bug.State == "Squashed" and b.Combo == 1 and b.Successes == 1)
	assert(BattleState.Kill(b, bug.Id, bug.SpawnAt + 1) == false, "already dead")
end

tests["kill within grace after reaching (lag)"] = function()
	local b = newBattle(0)
	local bug = minions(b)[1]
	assert(BattleState.Kill(b, bug.Id, bug.ReachAt + RULES.LatencyGrace - 0.05) == true)
	local late = newBattle(0)
	local lateBug = minions(late)[1]
	assert(BattleState.Kill(late, lateBug.Id, lateBug.ReachAt + RULES.LatencyGrace + 0.05) == false)
end

tests["kills can't outpace the fire rate"] = function()
	local b = newBattle(0)
	local list = minions(b)
	local t = 0
	for _, bug in list do
		t = math.max(t, bug.SpawnAt + RULES.VisibleDelay + 0.01)
	end
	-- every bug claimed at one instant: far more kills than shots fired so far
	local accepted = 0
	for _, bug in list do
		if BattleState.Kill(b, bug.Id, math.min(t, bug.ReachAt)) then
			accepted += 1
		end
	end
	local budget = math.floor(t / RULES.BaseFireInterval) + RULES.ShotBudgetSlack
	assert(accepted <= budget, `accepted {accepted} with budget {budget}`)
end

tests["boss takes many hits"] = function()
	local b = newBattle(3)
	local theBoss = boss(b)
	local t = theBoss.SpawnAt + RULES.VisibleDelay + 0.1
	clearMinionsUntil(b, t)
	for hit = 1, RULES.BossHp do
		assert(BattleState.Kill(b, theBoss.Id, t + hit * RULES.BaseFireInterval), `boss hit {hit}`)
	end
	assert(theBoss.Hp == 0 and theBoss.State == "Squashed")
end

tests["boss reaching your code hurts a lot"] = function()
	local b = newBattle(3)
	local theBoss = boss(b)
	clearMinionsUntil(b, math.huge)
	local before = b.Mood
	BattleState.Tick(b, theBoss.ReachAt + RULES.LatencyGrace + 0.01)
	assert(theBoss.State == "Hit" and b.Mood == before - RULES.BossHitPenalty)
end

tests["ships when every bug is dealt with"] = function()
	local b = newBattle(3)
	clearMinionsUntil(b, math.huge)
	local theBoss = boss(b)
	local t = math.max(theBoss.SpawnAt + RULES.VisibleDelay + 0.1, b.LastKillAt)
	for hit = 1, RULES.BossHp do
		BattleState.Kill(b, theBoss.Id, t + hit * RULES.BaseFireInterval)
	end
	assert(b.Status == "Shipped", `status {b.Status}`)
	local result = BattleState.Result(b)
	assert(result.Accuracy == 1 and result.Mistakes == 0 and result.Successes == #minions(b) + RULES.BossHp)
end

tests["fails at zero mood"] = function()
	local b = newBattle(0)
	BattleState.Tick(b, 200)
	assert(b.Status == "Failed")
end

tests["loadout from parts"] = function()
	local inventory = {
		FrontendUnits = grades(2, 0, 0, 0),
		BackendEndpoints = grades(1, 0, 0, 0),
		DatabaseTables = grades(0, 0, 0, 1),
		PromptTokens = grades(0, 1, 0, 0),
	}
	local loadout = BattleState.LoadoutFrom(inventory, RULES)
	assert(loadout.Shield == 3)
	assert(math.abs(loadout.FireInterval - (RULES.BaseFireInterval - 3 * RULES.FireIntervalPerQuality)) < 1e-9)
	assert(loadout.Rollback == false and loadout.Homing == true)
	local empty = BattleState.LoadoutFrom({}, RULES)
	assert(empty.Shield == 0 and empty.FireInterval == RULES.BaseFireInterval)
end

tests["snapshot"] = function()
	local b = newBattle(3)
	local bug = minions(b)[1]
	BattleState.Kill(b, bug.Id, bug.SpawnAt + RULES.VisibleDelay + 0.1)
	local snapshot = BattleState.Snapshot(b)
	assert(snapshot.Combo == 1 and snapshot.Progress > 0 and snapshot.Progress < 1)
	assert(snapshot.BugStates[bug.Id] == "Squashed" and snapshot.BossHp == RULES.BossHp and snapshot.Shield == 0)
end

tests["act tuning"] = function()
	local tuned = BattleState.RulesForAct(RULES, GameConfig.ACT_BATTLE[2])
	assert(tuned.Waves[1].Count == RULES.Waves[1].Count + 2)
	assert(math.abs(tuned.Waves[1].DiveTime - RULES.Waves[1].DiveTime * 0.85) < 1e-9)
	assert(math.abs(tuned.BossMinionDiveTime - RULES.BossMinionDiveTime * 0.85) < 1e-9)
	assert(tuned.BossHp == 20)
	assert(RULES.BossHp ~= 20 and RULES.Waves[1].Count ~= tuned.Waves[1].Count, "base rules mutated")
	assert(BattleState.RulesForAct(RULES, nil).BossHp == RULES.BossHp)
end

local function squadOptions(wingmen: { string }): BattleState.SquadOptions
	return { Wingmen = wingmen, EnemyKind = nil, BossVolleys = false, Squad = GameConfig.SQUAD }
end

local function squadBattle(wingmen: { string }): BattleState.Battle
	return BattleState.New(0, 0, BARE, RULES, makeRng(), squadOptions(wingmen))
end

tests["act 1 battles are unchanged"] = function()
	-- fingerprint of a fixed-seed Act 1 battle taken before squad options existed
	local b = BattleState.New(0, 0, BARE, RULES, makeRng())
	local sum = 0
	for _, bug in b.Bugs do
		sum += bug.SpawnX + bug.FormX + bug.DiveX + bug.ReachAt + bug.Side
	end
	assert(#b.Bugs == 27 and b.Mood == 70, `{#b.Bugs} bugs, mood {b.Mood}`)
	assert(math.abs(sum - 798.4176) < 1e-6, `fingerprint {sum}`)
	assert(b.Options == nil)
end

tests["ship moves are clamped to max speed"] = function()
	local b = squadBattle({})
	local t0 = 10
	BattleState.MoveShip(b, 0.5, t0)
	BattleState.MoveShip(b, 0.96, t0 + 0.05)
	assert(BattleState.ShipXAt(b, t0 + 0.05) <= 0.5 + 2.6 * 0.05 + 0.15 + 1e-9)
	BattleState.MoveShip(b, 5, t0 + 3)
	assert(BattleState.ShipXAt(b, t0 + 3) == 0.96, "clamped to the field")
end

tests["ship x is looked up by time"] = function()
	local b = squadBattle({})
	assert(BattleState.ShipXAt(b, 1) == 0.5, "no samples yet")
	local t0 = 10
	BattleState.MoveShip(b, 0.3, t0)
	BattleState.MoveShip(b, 0.4, t0 + 0.1)
	assert(BattleState.ShipXAt(b, t0 + 0.05) == 0.3)
	assert(BattleState.ShipXAt(b, t0 - 1) == 0.3, "before every sample")
	assert(BattleState.ShipXAt(b, t0 + 0.2) == 0.4)
end

tests["wingman weapons need the hire"] = function()
	local without = squadBattle({ "DatabaseTables" })
	local bug = minions(without)[1]
	local at = bug.SpawnAt + RULES.VisibleDelay + 0.1
	assert(BattleState.Kill(without, bug.Id, at, "Spread") == false, "no frontend wingman")
	assert(BattleState.Kill(newBattle(0), bug.Id, at, "Spread") == false, "act 1 has no wingmen")
	local with = squadBattle({ "FrontendUnits" })
	assert(BattleState.Kill(with, bug.Id, at, "Spread") == true)
	assert(BattleState.Kill(with, bug.Id + 1, at, "Nope" :: any) == false, "unknown weapon")
end

tests["wingman weapons have their own budget"] = function()
	local b = squadBattle({ "PromptTokens" })
	local list = minions(b)
	table.sort(list, function(x: BattleState.Bug, y: BattleState.Bug): boolean
		return x.SpawnAt < y.SpawnAt
	end)
	local missile = GameConfig.SQUAD.Weapons.Missile
	local accepted = 0
	-- claim every bug as it appears, then keep hitting the boss until the missile budget runs dry
	local function claim(bug: BattleState.Bug, at: number): boolean
		if BattleState.Kill(b, bug.Id, at, "Missile") then
			accepted += 1
			return true
		end
		local budget = math.floor(at / missile.Interval) * missile.PerShot + RULES.ShotBudgetSlack
		assert(accepted == budget, `rejected after {accepted} with budget {budget}`)
		assert(BattleState.Kill(b, bug.Id, at), "the ship's own budget is separate")
		return false
	end
	local theBoss = boss(b)
	local bossAt = theBoss.SpawnAt + RULES.VisibleDelay + 0.1
	for _, bug in list do
		local at = bug.SpawnAt + RULES.VisibleDelay + 0.01
		if at < bossAt and not claim(bug, at) then
			return
		end
	end
	for _ = 1, theBoss.Hp - 1 do
		if not claim(theBoss, bossAt) then
			return
		end
	end
	error("the missile budget never ran out")
end

local function landsAt(bug: BattleState.Bug): number
	return bug.ReachAt + RULES.LatencyGrace + 0.01
end

tests["wing shield absorbs a hit then recharges"] = function()
	local b = squadBattle({ "DatabaseTables" })
	local list = minions(b)
	table.sort(list, function(x: BattleState.Bug, y: BattleState.Bug): boolean
		return x.ReachAt < y.ReachAt
	end)
	local recharge = GameConfig.SQUAD.WingShieldRecharge
	local first, second = landsAt(list[1]), landsAt(list[2])
	assert(second - first < recharge, "fixture: second landing must come before the shield recharges")
	BattleState.Tick(b, first)
	assert(b.Mood == 70 and b.Mistakes == 1, `mood {b.Mood}`)
	BattleState.Tick(b, second)
	assert(b.Mood == 70 - RULES.MoodHitPenalty, `mood {b.Mood}`)

	-- the first landing after the recharge is absorbed again; everything in between counts as shot down
	local k = 3
	while landsAt(list[k]) < first + recharge do
		list[k].State = "Squashed"
		k += 1
	end
	assert(list[k + 1].ReachAt > list[k].ReachAt + 0.01, "fixture: one landing at a time")
	BattleState.Tick(b, landsAt(list[k]))
	assert(list[k].State == "Hit" and b.Mood == 70 - RULES.MoodHitPenalty, `mood {b.Mood}`)
end

tests["ship bursts can't stack slack"] = function()
	local b = squadBattle({})
	BattleState.MoveShip(b, 0.5, 10)
	for i = 0, 9 do
		BattleState.MoveShip(b, 0.96, 10 + i * 1e-6)
	end
	assert(BattleState.ShipXAt(b, 10.00001) <= 0.5 + 2.6 * 0.00001 + 0.15 + 1e-9, `x {BattleState.ShipXAt(b, 10.00001)}`)
	for _ = 1, 1000 do
		BattleState.MoveShip(b, 0.04, 10.00001)
	end
	assert(#b.ShipSamples <= 3, `{#b.ShipSamples} samples`)
end

tests["slowed ship moves at half speed"] = function()
	local b = squadBattle({})
	b.SlowUntil = 11
	BattleState.MoveShip(b, 0.5, 10)
	BattleState.MoveShip(b, 0.96, 10.1)
	assert(BattleState.ShipXAt(b, 10.1) <= 0.5 + 1.3 * 0.1 + 0.15 + 1e-9)
end

tests["bad ship times are ignored"] = function()
	local b = squadBattle({})
	BattleState.MoveShip(b, 0.5, 10)
	BattleState.MoveShip(b, 0.6, 0 / 0)
	BattleState.MoveShip(b, 0.6, 9)
	BattleState.MoveShip(b, 0 / 0, 10.5)
	assert(#b.ShipSamples == 1 and BattleState.ShipXAt(b, 20) == 0.5)
end

return tests
