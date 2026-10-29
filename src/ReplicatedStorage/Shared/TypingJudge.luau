--!strict
-- Pure: no requires, no Roblox APIs. The server judges typed prompts with this; the client never scores itself.

export type Grade = "S" | "A" | "B" | "C"

export type BurstRules = {
	TimeLimit: number,
	LatencyGrace: number,
	MaxCharsPerSecond: number,
	ForgivenEditsPerBurst: number,
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

function TypingJudge.JudgeBurst(
	prompts: { IssuedPrompt },
	submissions: { [number]: Submission },
	rules: BurstRules
): BurstResult
	if #prompts == 0 then
		return { Accuracy = 0, Completed = 0, Grade = "C", Flagged = false }
	end

	local deadline = prompts[1].IssuedAt + rules.TimeLimit + rules.LatencyGrace
	local forgivenLeft = rules.ForgivenEditsPerBurst
	local accuracySum = 0
	local completed = 0
	local flagged = false

	for index, prompt in prompts do
		local submission = submissions[index]
		if not submission or submission.ReceivedAt > deadline then
			continue
		end

		local elapsed = submission.ReceivedAt - prompt.IssuedAt
		if not TypingJudge.IsPlausible(#submission.Text, elapsed, rules.MaxCharsPerSecond) then
			flagged = true
			continue
		end

		local accuracy = TypingJudge.Accuracy(prompt.Text, submission.Text, 0)
		if accuracy < 1 and forgivenLeft > 0 then
			accuracy = TypingJudge.Accuracy(prompt.Text, submission.Text, forgivenLeft)
			forgivenLeft = 0
		end

		accuracySum += accuracy
		completed += 1
	end

	local accuracy = accuracySum / #prompts
	return {
		Accuracy = accuracy,
		Completed = completed,
		Grade = gradeFor(accuracy, completed == #prompts),
		Flagged = flagged,
	}
end

return TypingJudge
