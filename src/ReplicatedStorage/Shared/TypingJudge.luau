--!strict
-- Pure: no requires, no Roblox APIs. The server judges typed prompts with this; the client never scores itself.

export type Grade = "S" | "A" | "B" | "C"

-- How the countdown moves after each judged prompt: a clean prompt adds time (more for later prompts),
-- a sloppy one takes a little away.
export type TimeRules = {
	CleanAccuracy: number,
	CleanBonus: number,
	BonusPerPrompt: number,
	ErrorPenalty: number,
}

export type BurstRules = {
	TimeLimit: number,
	LatencyGrace: number,
	MaxCharsPerSecond: number,
	ForgivenEditsPerBurst: number,
	CleanAccuracy: number,
	CleanBonus: number,
	BonusPerPrompt: number,
	ErrorPenalty: number,
}

export type IssuedPrompt = { Text: string, IssuedAt: number }
export type Submission = { Text: string, ReceivedAt: number }

export type BurstResult = {
	Accuracy: number,
	Completed: number,
	Grade: Grade,
	Flagged: boolean,
}

local GRADE_S = 0.98
local GRADE_A = 0.93
local GRADE_B = 0.80

local TypingJudge = {}

function TypingJudge.Normalize(text: string): string
	local collapsed = string.gsub(string.lower(text), "%s+", " ")
	return (string.match(collapsed, "^%s*(.-)%s*$") or "")
end

local function levenshtein(a: string, b: string): number
	local lengthA, lengthB = #a, #b
	if lengthA == 0 then
		return lengthB
	end
	if lengthB == 0 then
		return lengthA
	end

	local previous: { number } = table.create(lengthB + 1, 0)
	local current: { number } = table.create(lengthB + 1, 0)
	for j = 0, lengthB do
		previous[j + 1] = j
	end

	for i = 1, lengthA do
		current[1] = i
		local byteA = string.byte(a, i)
		for j = 1, lengthB do
			local cost = if byteA == string.byte(b, j) then 0 else 1
			current[j + 1] = math.min(previous[j + 1] + 1, current[j] + 1, previous[j] + cost)
		end
		previous, current = current, previous
	end

	return previous[lengthB + 1]
end

function TypingJudge.Accuracy(expected: string, typed: string, forgivenEdits: number): number
	local cleanExpected = TypingJudge.Normalize(expected)
	local cleanTyped = TypingJudge.Normalize(typed)
	if #cleanTyped == 0 or #cleanTyped > 2 * #cleanExpected then
		return 0
	end

	local edits = math.max(0, levenshtein(cleanExpected, cleanTyped) - forgivenEdits)
	return math.max(0, 1 - edits / math.max(#cleanExpected, 1))
end

function TypingJudge.IsPlausible(charCount: number, elapsed: number, maxCharsPerSecond: number): boolean
	return elapsed > 0 and charCount / elapsed <= maxCharsPerSecond
end

function TypingJudge.TimeAdjustment(accuracy: number, promptNumber: number, rules: TimeRules): number
	if accuracy >= rules.CleanAccuracy then
		return rules.CleanBonus + rules.BonusPerPrompt * (promptNumber - 1)
	end
	return -rules.ErrorPenalty
end

local function gradeFor(accuracy: number, allCompleted: boolean): Grade
	if allCompleted and accuracy >= GRADE_S then
		return "S"
	elseif accuracy >= GRADE_A then
		return "A"
	elseif accuracy >= GRADE_B then
		return "B"
	end
	return "C"
end

type Walk = {
	AccuracySum: number,
	Completed: number,
	Flagged: boolean,
	Deadline: number,
}

-- Judges submissions in order while moving the deadline: each judged prompt adds or removes time.
-- A prompt is in time if it arrives before the deadline (plus latency grace) as it stood then.
local function walk(prompts: { IssuedPrompt }, submissions: { [number]: Submission }, rules: BurstRules): Walk
	local result: Walk = { AccuracySum = 0, Completed = 0, Flagged = false, Deadline = 0 }
	if #prompts == 0 then
		return result
	end

	result.Deadline = prompts[1].IssuedAt + rules.TimeLimit
	local forgivenLeft = rules.ForgivenEditsPerBurst

	for index, prompt in prompts do
		local submission = submissions[index]
		if not submission or submission.ReceivedAt > result.Deadline + rules.LatencyGrace then
			break
		end

		local accuracy = 0
		local elapsed = submission.ReceivedAt - prompt.IssuedAt
		if TypingJudge.IsPlausible(#submission.Text, elapsed, rules.MaxCharsPerSecond) then
			accuracy = TypingJudge.Accuracy(prompt.Text, submission.Text, 0)
			if accuracy < 1 and forgivenLeft > 0 then
				accuracy = TypingJudge.Accuracy(prompt.Text, submission.Text, forgivenLeft)
				forgivenLeft = 0
			end
			result.AccuracySum += accuracy
			result.Completed += 1
		else
			result.Flagged = true
		end

		result.Deadline += TypingJudge.TimeAdjustment(accuracy, index, rules)
	end

	return result
end

-- The burst's current deadline (without latency grace) given the submissions received so far.
function TypingJudge.BurstDeadline(
	prompts: { IssuedPrompt },
	submissions: { [number]: Submission },
	rules: BurstRules
): number
	return walk(prompts, submissions, rules).Deadline
end

function TypingJudge.JudgeBurst(
	prompts: { IssuedPrompt },
	submissions: { [number]: Submission },
	rules: BurstRules
): BurstResult
	if #prompts == 0 then
		return { Accuracy = 0, Completed = 0, Grade = "C", Flagged = false }
	end

	local walked = walk(prompts, submissions, rules)
	local completed = walked.Completed
	local flagged = walked.Flagged
	local accuracy = walked.AccuracySum / #prompts
	return {
		Accuracy = accuracy,
		Completed = completed,
		Grade = gradeFor(accuracy, completed == #prompts),
		Flagged = flagged,
	}
end

return TypingJudge
