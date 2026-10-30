--!strict
local PatchPanel = require("../src/ReplicatedStorage/Shared/PatchPanel")
local RaidRebuild = require("../src/ReplicatedStorage/Shared/RaidRebuild")
local TrainingRun = require("../src/ReplicatedStorage/Shared/TrainingRun")
local TypingJudge = require("../src/ReplicatedStorage/Shared/TypingJudge")

local function makeRng(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local tests = {}

-- Patch Panel -------------------------------------------------------------

tests["patch: rotating arms clockwise"] = function()
	-- N=1 E=2 S=4 W=8; a corner N+E rotated once becomes E+S
	assert(PatchPanel.Arms("Corner", 0) == 3)
	assert(PatchPanel.Arms("Corner", 1) == 6)
	assert(PatchPanel.Arms("Corner", 3) == 9)
	assert(PatchPanel.Arms("Straight", 1) == 10)
	assert(PatchPanel.Arms("Straight", 2) == 5)
end

tests["patch: generated puzzle has a solution and starts unsolved"] = function()
	for seed = 1, 25 do
		local puzzle = PatchPanel.Generate(5, 4, makeRng(seed))
		assert(#puzzle.Tiles == 20)
		assert(#puzzle.Solution == 20)
		assert(PatchPanel.Trace(puzzle, puzzle.Solution).Solved, `seed {seed}: solution does not solve`)
		assert(not PatchPanel.Trace(puzzle, puzzle.Start).Solved, `seed {seed}: starts solved`)
	end
end

tests["patch: trace counts connected path tiles from the router"] = function()
	local puzzle = PatchPanel.Generate(5, 4, makeRng(7))
	local full = PatchPanel.Trace(puzzle, puzzle.Solution)
	assert(full.Connected == puzzle.PathLength)
	assert(#full.Path == full.Connected and full.Path[1] == (puzzle.StartRow - 1) * 5 + 1)
	local broken = table.clone(puzzle.Solution)
	local firstIndex = (puzzle.StartRow - 1) * 5 + 1
	broken[firstIndex] = (broken[firstIndex] + 1) % 4
	local partial = PatchPanel.Trace(puzzle, broken)
	assert(not partial.Solved and partial.Connected < puzzle.PathLength)
end

tests["patch: score rewards fast solves and gives partial credit"] = function()
	assert(PatchPanel.Score(true, 5, 25, 20, 20) == 1)
	local slow = PatchPanel.Score(true, 22, 25, 20, 20)
	assert(slow < 0.93 and slow >= 0.8, `slow {slow}`)
	local unsolved = PatchPanel.Score(false, 25, 25, 10, 20)
	assert(math.abs(unsolved - 0.3) < 1e-9, `unsolved {unsolved}`)
end

-- RAID Rebuild ------------------------------------------------------------

tests["raid: sequence covers the longest round"] = function()
	local sequence = RaidRebuild.Generate(4, 6, makeRng(3))
	assert(#sequence == 6)
	for _, bay in sequence do
		assert(bay >= 1 and bay <= 4)
	end
end

tests["raid: round judging stops at the first wrong bay"] = function()
	local sequence = { 1, 3, 2, 4, 1 }
	local perfect = RaidRebuild.JudgeRound(sequence, 4, { 1, 3, 2, 4 })
	assert(perfect.Correct == 4 and perfect.Perfect)
	local wrong = RaidRebuild.JudgeRound(sequence, 4, { 1, 3, 4, 4 })
	assert(wrong.Correct == 2 and not wrong.Perfect)
	local short = RaidRebuild.JudgeRound(sequence, 4, { 1, 3 })
	assert(short.Correct == 2 and not short.Perfect)
	local junk = RaidRebuild.JudgeRound(sequence, 3, { "x" :: any, 3, 2 })
	assert(junk.Correct == 0)
end

tests["raid: input must come after the flash and at a human pace"] = function()
	assert(RaidRebuild.IsPlausible(10, 12, 4, 0.1) == true)
	assert(RaidRebuild.IsPlausible(10, 9.9, 4, 0.1) == false)
	assert(RaidRebuild.IsPlausible(10, 10.2, 4, 0.1) == false)
end

-- Training Run ------------------------------------------------------------

tests["training: needle oscillates between 0 and 1"] = function()
	local epoch = { Speed = 1, Phase = 0, ZoneCenter = 0.5, ZoneWidth = 0.2 }
	assert(math.abs(TrainingRun.NeedleAt(epoch, 0) - 0.5) < 1e-9)
	assert(math.abs(TrainingRun.NeedleAt(epoch, 0.25) - 1) < 1e-9)
	assert(math.abs(TrainingRun.NeedleAt(epoch, 0.75) - 0) < 1e-9)
end

tests["training: press quality by distance from the zone centre"] = function()
	local epoch = { Speed = 1, Phase = 0, ZoneCenter = 0.5, ZoneWidth = 0.2 }
	assert(TrainingRun.JudgePress(epoch, 0) == "Perfect") -- needle at 0.5
	assert(TrainingRun.JudgePress(epoch, 0.025) == "Good") -- needle about 0.578: inside the zone, off centre
	assert(TrainingRun.JudgePress(epoch, 0.25) == "Miss") -- needle at 1
	assert(TrainingRun.Value("Perfect") == 1 and TrainingRun.Value("Good") == 0.7 and TrainingRun.Value("Miss") == 0)
end

tests["training: claimed press time must match the server's view"] = function()
	assert(TrainingRun.IsPlausibleOffset(1.0, 1.2, 0.5, 0.05) == true)
	assert(TrainingRun.IsPlausibleOffset(1.0, 1.7, 0.5, 0.05) == false) -- claims an earlier press than lag allows
	assert(TrainingRun.IsPlausibleOffset(1.3, 1.2, 0.5, 0.05) == false) -- claims a press from the future
	assert(TrainingRun.IsPlausibleOffset(-0.1, 0.2, 0.5, 0.05) == false)
end

-- Shared grading ------------------------------------------------------------

tests["grading is shared with typing"] = function()
	assert(TypingJudge.GradeFor(1, true) == "S")
	assert(TypingJudge.GradeFor(1, false) == "A")
	assert(TypingJudge.GradeFor(0.85, true) == "B")
	assert(TypingJudge.GradeFor(0.2, false) == "C")
end

return tests
