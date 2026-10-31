--!strict
-- Pure: no requires, no Roblox APIs. Conference keynote (spec §9): type each campy slogan on its beat. Slogans
-- come from StoryText.KEYNOTE_SLOGANS (passed in). The server stamps every submission's At and judges it here.

export type Grade = "S" | "A" | "B" | "C"
export type Slogan = { Text: string, OpenAt: number, CloseAt: number } -- seconds since the round started
export type Round = { Slogans: { Slogan } }
export type Submission = { Text: string, At: number }
export type Result = { Correct: number, Total: number, Grade: Grade }

local Keynote = {}

local SLOGAN_COUNT = 8
local FIRST_OPEN = 4 -- camera move to the stage plus a read of the first slogan
local BEAT_SECONDS = 2.5
local WINDOW_SECONDS = 1.6
-- Server stamps land one network trip after the player's Enter; this much past CloseAt still counts.
Keynote.LATE_GRACE = 0.25
local REPUTATION: { [Grade]: number } = { S = 20, A = 12, B = 6, C = 0 }

function Keynote.New(rng: () -> number, bank: { string }): Round
	local pool = table.clone(bank)
	local slogans: { Slogan } = {}
	for index = 1, math.min(SLOGAN_COUNT, #pool) do
		local pick = math.min(#pool, math.floor(rng() * #pool) + 1)
		local text = table.remove(pool, pick) :: string
		local openAt = FIRST_OPEN + (index - 1) * BEAT_SECONDS
		table.insert(slogans, { Text = text, OpenAt = openAt, CloseAt = openAt + WINDOW_SECONDS })
	end
	return { Slogans = slogans }
end

-- The slogan whose window (plus LATE_GRACE) holds `at`, or nil between beats. Windows never overlap.
function Keynote.WindowAt(round: Round, at: number): number?
	for index, slogan in round.Slogans do
		if at >= slogan.OpenAt and at <= slogan.CloseAt + Keynote.LATE_GRACE then
			return index
		end
	end
	return nil
end

-- Case, spacing and punctuation don't count: phone keyboards add curly apostrophes and trailing spaces.
function Keynote.Matches(typed: string, slogan: string): boolean
	local function letters(text: string): string
		return (string.gsub(string.lower(text), "[^%w]", ""))
	end
	return letters(typed) ~= "" and letters(typed) == letters(slogan)
end

-- shortcut: Grade duplicated in Firewall/Triage/ClapBack/Keynote (pure modules cannot require each other), keep thresholds in sync.
function Keynote.Grade(correct: number, total: number): Grade
	local ratio = if total > 0 then correct / total else 0
	if ratio >= 0.95 then
		return "S"
	elseif ratio >= 0.8 then
		return "A"
	elseif ratio >= 0.6 then
		return "B"
	end
	return "C"
end

-- submissions is built from client data: ignore anything malformed.
function Keynote.Judge(round: Round, submissions: { [number]: Submission }): Result
	local correct = 0
	for index, slogan in round.Slogans do
		local entry = submissions[index]
		if type(entry) ~= "table" or type(entry.Text) ~= "string" or type(entry.At) ~= "number" then
			continue
		end
		if entry.At >= slogan.OpenAt and entry.At <= slogan.CloseAt + Keynote.LATE_GRACE and Keynote.Matches(entry.Text, slogan.Text) then
			correct += 1
		end
	end
	return { Correct = correct, Total = #round.Slogans, Grade = Keynote.Grade(correct, #round.Slogans) }
end

function Keynote.RepFor(grade: Grade): number
	return REPUTATION[grade] or 0
end

return Keynote
