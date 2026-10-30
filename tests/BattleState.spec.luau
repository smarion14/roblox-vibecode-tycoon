--!strict
local BattleState = require("../src/ReplicatedStorage/Shared/BattleState")
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local PromptBank = require("../src/ReplicatedStorage/Shared/PromptBank")

local RULES = GameConfig.BATTLE_RULES
local BOSS_PHRASE = "memory overflow in production"

-- Deterministic stand-in for Random: steps through (n * 0.37) % 1 so consecutive bugs get different words.
local function makeRng(): () -> number
	local n = 0
	return function(): number
		n += 1
		return (n * 0.37) % 1
	end
end

local function newBattle(avgQuality: number, rules: BattleState.BattleRules?): BattleState.Battle
	return BattleState.New(0, avgQuality, PromptBank.BUG_WORDS, BOSS_PHRASE, rules or RULES, makeRng())
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

local function assertDistinctEarlyWords(b: BattleState.Battle)
	for i = 2, 4 do
		assert(b.Bugs[i].Word ~= b.Bugs[1].Word, "test precondition: early bug words must differ")
	end
end

local tests = {}

tests["start mood from quality"] = function()
	assert(newBattle(0).Mood == 70)
	assert(newBattle(3).Mood == 100)
end

tests["first bug timing"] = function()
	local b = newBattle(3)
	assert(b.Bugs[1].SpawnAt == RULES.FirstBugDelay)
	assert(b.Bugs[1].ReachAt == RULES.FirstBugDelay + RULES.Waves[1].Travel)
	assert(b.Bugs[1].Wave == 1)
end

tests["waves then one boss with a health point per word"] = function()
	local b = newBattle(3)
	local list = minions(b)
	assert(#list >= RULES.Waves[1].Count + RULES.Waves[2].Count, `only {#list} minions`)
	local theBoss = boss(b)
	assert(theBoss.Hp == 4 and #theBoss.Words == 4)
	assert(theBoss.Wave == #RULES.Waves + 1)
	-- the boss arrives after both regular waves have started spawning
	for _, bug in list do
		if bug.Wave <= #RULES.Waves then
			assert(bug.SpawnAt < theBoss.SpawnAt, "regular wave bug spawned after the boss")
		end
	end
end

tests["sloppy components bring more bugs"] = function()
	assert(#minions(newBattle(0)) > #minions(newBattle(3)))
end

tests["bug hit after grace"] = function()
	local b = newBattle(0)
	local first = b.Bugs[1]
	BattleState.Tick(b, first.ReachAt + RULES.LatencyGrace - 0.01)
	assert(first.State == "Pending")
	BattleState.Tick(b, first.ReachAt + RULES.LatencyGrace + 0.01)
	assert(first.State == "Hit")
	assert(b.Mood == 70 - RULES.MoodHitPenalty)
end

tests["squash within grace (lag)"] = function()
	local b = newBattle(0)
	assertDistinctEarlyWords(b)
	local first = b.Bugs[1]
	assert(BattleState.Squash(b, first.Word, first.ReachAt + RULES.LatencyGrace - 0.05) == true)
	assert(first.State == "Squashed" and b.Combo == 1 and b.MaxCombo == 1)

	local late = newBattle(0)
	assert(BattleState.Squash(late, late.Bugs[1].Word, late.Bugs[1].ReachAt + RULES.LatencyGrace + 0.05) == false)
	assert(late.Bugs[1].State == "Hit")
end

tests["squash is case and space tolerant"] = function()
	local b = newBattle(0)
	local first = b.Bugs[1]
	assert(BattleState.Squash(b, "  " .. string.upper(first.Word) .. " ", first.SpawnAt + 1) == true)
end

tests["squash faster than typing the word fails"] = function()
	local b = newBattle(0)
	local first = b.Bugs[1]
	assert(BattleState.Squash(b, first.Word, first.SpawnAt + 0.05) == false)
	assert(first.State == "Pending")
	assert(BattleState.Squash(b, first.Word, first.SpawnAt + 0.5) == true)
end

tests["missed squash costs mood and combo"] = function()
	local b = newBattle(0)
	local first = b.Bugs[1]
	BattleState.Squash(b, first.Word, first.SpawnAt + 1)
	assert(b.Combo == 1)
	BattleState.Squash(b, "notabug", first.SpawnAt + 1.5)
	assert(b.Combo == 0)
	assert(b.Mood == 70 - RULES.MissedSquashPenalty, `mood {b.Mood}`)
end

tests["boss words must be typed in order"] = function()
	local b = newBattle(3)
	local theBoss = boss(b)
	local t = theBoss.SpawnAt + 1
	-- clear the regular waves first so the client is still on the call when the boss arrives
	for _, bug in minions(b) do
		if bug.SpawnAt + 0.6 < t then
			BattleState.Squash(b, bug.Word, bug.SpawnAt + 0.6)
		end
	end
	assert(BattleState.Squash(b, "overflow", t) == false, "second word hit before the first")
	assert(theBoss.Hp == 4)
	assert(BattleState.Squash(b, "memory", t + 0.5) == true)
	assert(theBoss.Hp == 3 and theBoss.State == "Pending")
	assert(BattleState.Squash(b, "overflow", t + 1.2) == true)
	assert(BattleState.Squash(b, "in", t + 1.5) == true)
	assert(BattleState.Squash(b, "production", t + 2.5) == true)
	assert(theBoss.Hp == 0 and theBoss.State == "Squashed")
end

tests["boss reaching your code hurts a lot"] = function()
	local b = newBattle(3)
	local theBoss = boss(b)
	-- squash every minion so only the boss can hurt
	for _, bug in minions(b) do
		BattleState.Squash(b, bug.Word, bug.SpawnAt + 0.6)
	end
	local moodBefore = b.Mood
	BattleState.Tick(b, theBoss.ReachAt + RULES.LatencyGrace + 0.01)
	assert(theBoss.State == "Hit")
	assert(b.Mood == moodBefore - RULES.BossHitPenalty, `mood {b.Mood}`)
end

tests["ships when every bug is dealt with"] = function()
	local b = newBattle(3)
	type Event = { At: number, Word: string }
	local events: { Event } = {}
	for _, bug in b.Bugs do
		if bug.Kind == "Minion" then
			table.insert(events, { At = bug.SpawnAt + 0.6, Word = bug.Word })
		else
			for index, word in bug.Words do
				table.insert(events, { At = bug.SpawnAt + 0.7 * index, Word = word })
			end
		end
	end
	table.sort(events, function(a: Event, c: Event): boolean
		return a.At < c.At
	end)
	for _, event in events do
		BattleState.Squash(b, event.Word, event.At)
	end
	assert(b.Status == "Shipped", `status {b.Status}`)
	local result = BattleState.Result(b)
	assert(result.Status == "Shipped" and result.Accuracy == 1 and result.MoodRatio == 1)
	assert(result.MaxCombo == #events, `max combo {result.MaxCombo} of {#events}`)
end

tests["fails at zero mood"] = function()
	local b = newBattle(0)
	BattleState.Tick(b, 40)
	assert(b.Status == "Failed", `status {b.Status}`)
end

tests["finished battle ignores input"] = function()
	local b = newBattle(0)
	BattleState.Tick(b, 40)
	local last = b.Bugs[#b.Bugs]
	assert(BattleState.Squash(b, last.Word, last.SpawnAt + 1) == false)
end

tests["snapshot"] = function()
	local b = newBattle(3)
	local first = b.Bugs[1]
	BattleState.Squash(b, first.Word, first.SpawnAt + 1)
	local snapshot = BattleState.Snapshot(b)
	assert(snapshot.Mood == 100 and snapshot.Combo == 1)
	assert(snapshot.Progress > 0 and snapshot.Progress < 1)
	assert(snapshot.BugStates[first.Id] == "Squashed")
	assert(snapshot.BossHp == 4)
	assert(snapshot.Status == "Running")
end

return tests
