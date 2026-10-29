--!strict
local BattleState = require("../src/ReplicatedStorage/Shared/BattleState")
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")
local PromptBank = require("../src/ReplicatedStorage/Shared/PromptBank")
local TypingJudge = require("../src/ReplicatedStorage/Shared/TypingJudge")

local RULES = GameConfig.BATTLE_RULES
local JUDGE: BattleState.Judge = { Accuracy = TypingJudge.Accuracy, IsPlausible = TypingJudge.IsPlausible }

-- Deterministic stand-in for Random: steps through (n * 0.37) % 1 so consecutive bugs get different words.
local function makeRng(): () -> number
	local n = 0
	return function(): number
		n += 1
		return (n * 0.37) % 1
	end
end

local function newBattle(avgQuality: number, rules: BattleState.BattleRules?): BattleState.Battle
	return BattleState.New(0, avgQuality, PromptBank.BATTLE_PROMPTS, PromptBank.BUG_WORDS, rules or RULES, makeRng())
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
	local b = newBattle(0)
	assert(b.Bugs[1].SpawnAt == 2)
	assert(b.Bugs[1].ReachAt == 8)
	assert(math.abs(b.Bugs[2].SpawnAt - 3.6) < 1e-9)
end

tests["bug hit after grace"] = function()
	local b = newBattle(0)
	BattleState.Tick(b, 8.24)
	assert(b.Bugs[1].State == "Pending")
	BattleState.Tick(b, 8.26)
	assert(b.Bugs[1].State == "Hit")
	assert(b.Mood == 55)
end

tests["squash within grace (lag)"] = function()
	local b = newBattle(0)
	assertDistinctEarlyWords(b)
	assert(BattleState.Squash(b, b.Bugs[1].Word, 8.2) == true)
	assert(b.Bugs[1].State == "Squashed" and b.Combo == 1 and b.MaxCombo == 1)

	local late = newBattle(0)
	assert(BattleState.Squash(late, late.Bugs[1].Word, 8.3) == false)
	assert(late.Bugs[1].State == "Hit")
end

tests["squash before spawn fails"] = function()
	local b = newBattle(0)
	assertDistinctEarlyWords(b)
	assert(BattleState.Squash(b, "  " .. string.upper(b.Bugs[1].Word) .. " ", 3) == true)
	assert(b.Combo == 1)
	assert(BattleState.Squash(b, b.Bugs[2].Word, 3.1) == false)
	assert(b.Combo == 0)
	assert(b.Bugs[2].State == "Pending")
end

tests["clean prompt"] = function()
	local b = newBattle(0)
	local accuracy = BattleState.SubmitPrompt(b, b.Prompts[1], 4, JUDGE)
	assert(accuracy == 1)
	assert(b.Progress == 1 and b.Combo == 1)
	assert(b.PromptIndex == 2 and b.PromptIssuedAt == 4)
end

tests["garbage prompt"] = function()
	local b = newBattle(0)
	BattleState.SubmitPrompt(b, "zzzz", 1, JUDGE)
	assert(b.Progress == 0)
	assert(b.Mood == 65)
	assert(b.PromptIndex == 1 and b.PromptIssuedAt == 1)
end

tests["superhuman prompt"] = function()
	local b = newBattle(0)
	assert(BattleState.SubmitPrompt(b, b.Prompts[1], 0.5, JUDGE) == 0)
end

tests["ships after 4 clean prompts"] = function()
	local b = newBattle(3)
	for i = 1, 4 do
		BattleState.SubmitPrompt(b, b.Prompts[b.PromptIndex], i * 4, JUDGE)
	end
	assert(b.Status == "Shipped", `status {b.Status}`)
	assert(b.Mood == 40, `mood {b.Mood}`)
	local result = BattleState.Result(b)
	-- bugs reaching the prompt between submits reset the combo, so the best streak is the first two prompts
	assert(result.Status == "Shipped" and result.Accuracy == 1 and result.MaxCombo == 2)
	assert(result.MoodRatio == 0.4)
end

tests["fails at zero mood"] = function()
	local b = newBattle(0)
	BattleState.Tick(b, 15)
	assert(b.Status == "Failed", `status {b.Status}`)
end

tests["fails on timeout"] = function()
	local rules = table.clone(RULES)
	rules.BugTravelTime = 1000
	local b = newBattle(3, rules)
	BattleState.Tick(b, 119)
	assert(b.Status == "Running")
	BattleState.Tick(b, 121)
	assert(b.Status == "Failed")
end

tests["finished battle ignores input"] = function()
	local b = newBattle(0)
	BattleState.Tick(b, 15)
	assert(BattleState.SubmitPrompt(b, b.Prompts[b.PromptIndex], 20, JUDGE) == 0)
	assert(b.Progress == 0)
end

tests["snapshot"] = function()
	local b = newBattle(0)
	BattleState.Squash(b, b.Bugs[1].Word, 3)
	local snapshot = BattleState.Snapshot(b)
	assert(snapshot.Mood == 70 and snapshot.Combo == 1 and snapshot.Progress == 0)
	assert(snapshot.PromptText == b.Prompts[1])
	assert(snapshot.BugStates[b.Bugs[1].Id] == "Squashed")
	assert(snapshot.Status == "Running")
end

return tests
