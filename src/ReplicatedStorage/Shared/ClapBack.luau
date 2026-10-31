--!strict
-- Pure: no requires, no Roblox APIs. Clap-back incident minigame: answer angry posts with the best of three
-- replies. The post bank (ServerStorage IncidentBanks.CLAPBACK_POSTS) is passed in through options.Bank.

export type Grade = "S" | "A" | "B" | "C"
export type BankEntry = { Post: string, Replies: { string }, Best: number }
export type Post = { Post: string, Replies: { string }, Best: number } -- Best: index into the shuffled Replies
export type Round = { Posts: { Post } }
export type Result = { Correct: number, Total: number }

local ClapBack = {}

local FULL_COUNT = 5
local SHORT_COUNT = 3 -- with the PR Lead

local function shuffledIndices(count: number, rng: () -> number): { number }
	local order: { number } = {}
	for i = 1, count do
		order[i] = i
	end
	for i = count, 2, -1 do -- Fisher-Yates
		local j = math.min(i, math.floor(rng() * i) + 1)
		order[i], order[j] = order[j], order[i]
	end
	return order
end

-- options: { Short: boolean?, Bank: { BankEntry } }
function ClapBack.New(rng: () -> number, options: { [string]: any }): Round
	local bank = options.Bank :: { BankEntry }
	local order = shuffledIndices(#bank, rng)
	local count = math.min(if options.Short then SHORT_COUNT else FULL_COUNT, #bank)
	local posts: { Post } = {}
	for i = 1, count do
		local entry = bank[order[i]]
		local replies: { string } = {}
		local best = 1
		for slot, original in shuffledIndices(#entry.Replies, rng) do
			replies[slot] = entry.Replies[original]
			if original == entry.Best then
				best = slot
			end
		end
		table.insert(posts, { Post = entry.Post, Replies = replies, Best = best })
	end
	return { Posts = posts }
end

-- inputs is client data: { [postIndex]: replyIndex }
function ClapBack.Judge(round: Round, inputs: { [number]: number }): Result
	local correct = 0
	if type(inputs) == "table" then
		for index, post in round.Posts do
			if inputs[index] == post.Best then
				correct += 1
			end
		end
	end
	return { Correct = correct, Total = #round.Posts }
end

-- shortcut: Grade duplicated in Firewall/Triage/ClapBack (pure modules cannot require each other), keep thresholds in sync.
function ClapBack.Grade(correct: number, total: number): Grade
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

return ClapBack
