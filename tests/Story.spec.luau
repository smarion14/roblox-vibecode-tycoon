--!strict
local Story = require("../src/ReplicatedStorage/Shared/Story")
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")

local function state(act: number, seenIntro: boolean, rentPaid: boolean, flags: { [string]: boolean }?): Story.StoryState
	return { Act = act, SeenIntro = seenIntro, RentPaid = rentPaid, Flags = flags or {} }
end

local tests = {}

tests["next beat for a fresh save"] = function()
	assert(Story.NextBeat(state(1, false, false)) == "Act1Intro")
end

tests["act 1 done but not moved (also an old save)"] = function()
	assert(Story.NextBeat(state(1, true, true)) == "Act1End")
	assert(Story.NextBeat(state(1, false, true)) == "Act1End")
end

tests["act 2 without its opening seen (left mid-cutscene)"] = function()
	assert(Story.NextBeat(state(2, true, true)) == "Act2Intro")
end

tests["nothing pending"] = function()
	assert(Story.NextBeat(state(2, true, true, { Act2IntroSeen = true })) == nil)
	assert(Story.NextBeat(state(1, true, false)) == nil)
end

tests["accept done only in order"] = function()
	local paid = state(1, true, true)
	assert(Story.AcceptDone(paid, "Act2Intro") == false)
	assert(Story.AcceptDone(paid, "Act1End") == true)
	assert(Story.AcceptDone(state(2, true, true, { Act2IntroSeen = true }), "Act2Intro") == false)
end

tests["act 2 start"] = function()
	local start = Story.Act2Start(1.6, 1.5)
	assert(start.Act == 2 and start.ActDeploys == 0)
	assert(math.abs(start.ActGoal - 3.1) < 1e-9)
end

tests["goal reached"] = function()
	assert(Story.ActGoalReached(1, 9, 3) == false)
	assert(Story.ActGoalReached(2, 3.1, 3.1) == true)
	assert(Story.ActGoalReached(2, 3.0, 3.1) == false)
end

tests["precheck names"] = function()
	assert(Story.PrecheckName("  my   app ") == "my app")
	local clean, reason = Story.PrecheckName("ab")
	assert(clean == nil and reason == "Too short")
	local _, long = Story.PrecheckName(string.rep("a", 25))
	assert(long == "Too long")
	local _, blank = Story.PrecheckName("   ")
	assert(blank == "Too short")
	local _, emoji = Story.PrecheckName("🚀🚀🚀")
	assert(emoji == "Letters or numbers only")
end

local function act2(overrides: { [string]: any }): Story.MilestoneState
	local state: Story.MilestoneState = {
		Act = 2,
		ActDeploys = 0,
		Valuation = 1.2,
		ActGoal = 2.7,
		Hires = 0,
		Flags = {},
	}
	for key, value in overrides do
		(state :: any)[key] = value
	end
	return state
end

local STEP = GameConfig.ACT2.ValuationStep

tests["no milestones at the start of act 2"] = function()
	assert(#Story.NewMilestones(GameConfig.ACT2.Milestones, act2({}), STEP) == 0)
end

tests["first hire is a milestone"] = function()
	local ids = Story.NewMilestones(GameConfig.ACT2.Milestones, act2({ Hires = 1 }), STEP)
	assert(table.find(ids, "FirstHire"))
end

tests["halfway to the valuation goal is a milestone"] = function()
	local ids = Story.NewMilestones(GameConfig.ACT2.Milestones, act2({ Valuation = 1.95 }), STEP)
	assert(table.find(ids, "Halfway"))
	assert(not table.find(Story.NewMilestones(GameConfig.ACT2.Milestones, act2({ Valuation = 1.9 }), STEP), "Halfway"))
end

tests["a milestone fires once"] = function()
	local ids = Story.NewMilestones(GameConfig.ACT2.Milestones, act2({ Hires = 2, Flags = { Milestone_FirstHire = true } }), STEP)
	assert(not table.find(ids, "FirstHire"))
end

tests["act 1 has no act 2 milestones"] = function()
	assert(#Story.NewMilestones(GameConfig.ACT2.Milestones, act2({ Act = 1, Hires = 3, ActDeploys = 9 }), STEP) == 0)
end

tests["client milestones match when act 2 clients unlock"] = function()
	local unlocks: { [number]: boolean } = {}
	for _, client in GameConfig.CLIENTS do
		if client.Act == 2 and client.UnlockAtDeploys > 0 then
			unlocks[client.UnlockAtDeploys] = true
		end
	end
	for _, milestone in GameConfig.ACT2.Milestones do
		if milestone.Kind == "ActDeploys" then
			assert(unlocks[milestone.At], `{milestone.Id} fires at {milestone.At} deploys but no client unlocks there`)
			unlocks[milestone.At] = nil
		end
	end
	assert(next(unlocks) == nil, "an act 2 client unlock has no milestone")
end

return tests
