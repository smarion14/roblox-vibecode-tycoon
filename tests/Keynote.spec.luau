--!strict
local Keynote = require("../src/ReplicatedStorage/Shared/Keynote")
local StoryText = require("../src/ReplicatedStorage/Shared/StoryText")

local function makeRng(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function newRound(): Keynote.Round
	return Keynote.New(makeRng(7), StoryText.KEYNOTE_SLOGANS)
end

local tests = {}

tests["keynote windows are steady"] = function()
	local round = newRound()
	assert(#round.Slogans == 8, `expected 8 slogans, got {#round.Slogans}`)
	local seen: { [string]: boolean } = {}
	for index, slogan in round.Slogans do
		assert(not seen[slogan.Text], `duplicate slogan {slogan.Text}`)
		seen[slogan.Text] = true
		assert(math.abs(slogan.CloseAt - slogan.OpenAt - 1.6) < 1e-9, "window is 1.6 s wide")
		if index > 1 then
			assert(math.abs(slogan.OpenAt - round.Slogans[index - 1].OpenAt - 2.5) < 1e-9, "windows are 2.5 s apart")
		end
	end
	assert(#StoryText.KEYNOTE_SLOGANS >= 8)
end

tests["typing on time counts"] = function()
	local round = newRound()
	local slogan = round.Slogans[1]
	local middle = (slogan.OpenAt + slogan.CloseAt) / 2
	assert(Keynote.WindowAt(round, middle) == 1)
	local lower = Keynote.Judge(round, { [1] = { Text = string.lower(slogan.Text), At = middle } })
	assert(lower.Correct == 1 and lower.Total == 8)
	local edge = Keynote.Judge(round, { [1] = { Text = `  {slogan.Text} `, At = slogan.OpenAt } })
	assert(edge.Correct == 1, "padding is ignored and the window opens inclusive")
	assert(Keynote.Matches("were-hiring", "WE'RE HIRING"), "punctuation and spacing are ignored")
end

tests["late or wrong text misses"] = function()
	local round = newRound()
	local slogan = round.Slogans[2]
	assert(Keynote.WindowAt(round, slogan.CloseAt + 0.5) == nil, "no window between beats")
	assert(Keynote.WindowAt(round, slogan.OpenAt - 0.1) == nil)
	local late = Keynote.Judge(round, { [2] = { Text = slogan.Text, At = slogan.CloseAt + 0.5 } })
	local early = Keynote.Judge(round, { [2] = { Text = slogan.Text, At = slogan.OpenAt - 0.1 } })
	local wrong = Keynote.Judge(round, { [2] = { Text = "NOT THE SLOGAN", At = slogan.OpenAt + 0.5 } })
	local garbage = Keynote.Judge(round, { [2] = { Text = 5, At = 0 / 0 } :: any, [99] = "x" :: any })
	assert(late.Correct == 0 and early.Correct == 0 and wrong.Correct == 0 and garbage.Correct == 0)
end

tests["late grace boundary"] = function()
	local round = newRound()
	local slogan = round.Slogans[3]
	local justLate = Keynote.Judge(round, { [3] = { Text = slogan.Text, At = slogan.CloseAt + 0.2 } })
	local tooLate = Keynote.Judge(round, { [3] = { Text = slogan.Text, At = slogan.CloseAt + 0.3 } })
	assert(justLate.Correct == 1, "CloseAt + 0.2 still counts")
	assert(tooLate.Correct == 0, "CloseAt + 0.3 misses")
	assert(Keynote.WindowAt(round, slogan.CloseAt + 0.2) == 3 and Keynote.WindowAt(round, slogan.CloseAt + 0.3) == nil)
end

tests["grade and reputation"] = function()
	local round = newRound()
	local all: { [number]: Keynote.Submission } = {}
	for index, slogan in round.Slogans do
		all[index] = { Text = slogan.Text, At = slogan.OpenAt + 0.8 }
	end
	local perfect = Keynote.Judge(round, all)
	assert(perfect.Correct == 8 and perfect.Grade == "S")
	assert(Keynote.RepFor(perfect.Grade) == 20)
	all[6], all[7], all[8] = nil, nil, nil
	local five = Keynote.Judge(round, all)
	assert(five.Correct == 5 and five.Grade == "B", `5/8 graded {five.Grade}`)
	assert(Keynote.RepFor(five.Grade) == 6)
	assert(Keynote.RepFor("A") == 12 and Keynote.RepFor("C") == 0)
end

return tests
