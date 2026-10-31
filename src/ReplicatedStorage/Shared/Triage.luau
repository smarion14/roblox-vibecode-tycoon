--!strict
-- Pure: no requires, no Roblox APIs. Triage incident minigame: sort bug reports into Critical, Minor or
-- NotABug. The report bank (ServerStorage IncidentBanks.TRIAGE_REPORTS) is passed in through options.Bank.

export type Grade = "S" | "A" | "B" | "C"
export type Answer = "Critical" | "Minor" | "NotABug"
export type BankEntry = { Text: string, Answer: Answer }
export type Report = { Id: number, Text: string, Answer: Answer }
export type Round = { Reports: { Report } }
export type Result = { Correct: number, Total: number }

local Triage = {}

local FULL_COUNT = 10
local SHORT_COUNT = 6 -- with the QA Manager

-- options: { Short: boolean?, Bank: { BankEntry } }
function Triage.New(rng: () -> number, options: { [string]: any }): Round
	local bank = options.Bank :: { BankEntry }
	local order: { number } = {}
	for i = 1, #bank do
		order[i] = i
	end
	for i = #order, 2, -1 do -- Fisher-Yates
		local j = math.min(i, math.floor(rng() * i) + 1)
		order[i], order[j] = order[j], order[i]
	end
	local count = math.min(if options.Short then SHORT_COUNT else FULL_COUNT, #bank)
	local reports: { Report } = {}
	for id = 1, count do
		local entry = bank[order[id]]
		table.insert(reports, { Id = id, Text = entry.Text, Answer = entry.Answer })
	end
	return { Reports = reports }
end

-- inputs is client data: { [id]: answer }
function Triage.Judge(round: Round, inputs: { [number]: string }): Result
	local correct = 0
	if type(inputs) == "table" then
		for _, report in round.Reports do
			if inputs[report.Id] == report.Answer then
				correct += 1
			end
		end
	end
	return { Correct = correct, Total = #round.Reports }
end

-- shortcut: Grade duplicated in Firewall/Triage/ClapBack (pure modules cannot require each other), keep thresholds in sync.
function Triage.Grade(correct: number, total: number): Grade
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

return Triage
