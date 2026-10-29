--!strict
local TypingJudge = require("../src/ReplicatedStorage/Shared/TypingJudge")

local RULES = { TimeLimit = 10, LatencyGrace = 0.5, MaxCharsPerSecond = 20, ForgivenEditsPerBurst = 0 }
local TEXTS = {
	"make the navbar sticky on scroll",
	"add a dark mode toggle to the header",
	"center the hero image on mobile",
}

local function issued(): { TypingJudge.IssuedPrompt }
	return {
		{ Text = TEXTS[1], IssuedAt = 0 },
		{ Text = TEXTS[2], IssuedAt = 3 },
		{ Text = TEXTS[3], IssuedAt = 6 },
	}
end

local function perfectSubmissions(): { [number]: TypingJudge.Submission }
	return {
		{ Text = TEXTS[1], ReceivedAt = 2.9 },
		{ Text = TEXTS[2], ReceivedAt = 5.9 },
		{ Text = TEXTS[3], ReceivedAt = 8.9 },
	}
end

local tests = {}

tests["normalize"] = function()
	assert(TypingJudge.Normalize("  Make   the NAVBAR sticky ") == "make the navbar sticky")
end

tests["exact match"] = function()
	assert(TypingJudge.Accuracy("abc", "abc", 0) == 1)
end

tests["one substitution"] = function()
	assert(TypingJudge.Accuracy("abcd", "abed", 0) == 0.75)
end

tests["forgiven edit"] = function()
	assert(TypingJudge.Accuracy("abcd", "abed", 1) == 1)
end

tests["empty typed"] = function()
	assert(TypingJudge.Accuracy("abc", "", 0) == 0)
end

tests["huge paste"] = function()
	assert(TypingJudge.Accuracy("ab", string.rep("x", 5), 0) == 0)
end

tests["emoji does not crash"] = function()
	local accuracy = TypingJudge.Accuracy("add a button", "add a button 🚀", 0)
	assert(accuracy > 0 and accuracy < 1, `got {accuracy}`)
end

tests["plausibility"] = function()
	assert(TypingJudge.IsPlausible(20, 1, 20) == true)
	assert(TypingJudge.IsPlausible(21, 1, 20) == false)
	assert(TypingJudge.IsPlausible(5, 0, 20) == false)
end

tests["perfect burst is S"] = function()
	local result = TypingJudge.JudgeBurst(issued(), perfectSubmissions(), RULES)
	assert(result.Grade == "S", `grade {result.Grade}`)
	assert(result.Accuracy == 1)
	assert(result.Completed == 3)
	assert(result.Flagged == false)
end

tests["late submission scores zero"] = function()
	local submissions = perfectSubmissions()
	submissions[3] = { Text = TEXTS[3], ReceivedAt = 10.51 }
	local result = TypingJudge.JudgeBurst(issued(), submissions, RULES)
	assert(result.Completed == 2, `completed {result.Completed}`)
	assert(result.Grade ~= "S")
end

tests["missing submission"] = function()
	local submissions = perfectSubmissions()
	submissions[3] = nil
	local result = TypingJudge.JudgeBurst(issued(), submissions, RULES)
	assert(result.Completed == 2, `completed {result.Completed}`)
end

tests["superhuman speed flagged"] = function()
	local prompts = { { Text = "make the navbar sticky on scroll and fast", IssuedAt = 0 } }
	local submissions = { { Text = "make the navbar sticky on scroll and fast", ReceivedAt = 0.5 } }
	local result = TypingJudge.JudgeBurst(prompts, submissions, RULES)
	assert(result.Flagged == true)
	assert(result.Accuracy == 0)
end

tests["forgiven once per burst"] = function()
	local rules = table.clone(RULES)
	rules.ForgivenEditsPerBurst = 1
	local prompts = {
		{ Text = "abcdefghij", IssuedAt = 0 },
		{ Text = "klmnopqrst", IssuedAt = 3 },
	}
	local submissions = {
		{ Text = "abcdefghiX", ReceivedAt = 2 },
		{ Text = "klmnopqrsX", ReceivedAt = 5 },
	}
	local result = TypingJudge.JudgeBurst(prompts, submissions, rules)
	-- first prompt forgiven to 1.0, second 0.9 → mean 0.95
	assert(math.abs(result.Accuracy - 0.95) < 1e-9, `accuracy {result.Accuracy}`)
end

return tests
