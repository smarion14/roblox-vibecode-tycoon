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

return tests
