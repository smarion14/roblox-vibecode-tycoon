--!strict
local ClapBack = require("../src/ReplicatedStorage/Shared/ClapBack")
local Firewall = require("../src/ReplicatedStorage/Shared/Firewall")
local IncidentBanks = require("../src/ServerStorage/IncidentBanks")
local Triage = require("../src/ReplicatedStorage/Shared/Triage")

local function makeRng(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local tests = {}

tests["firewall perfect play grades S"] = function()
	local round = Firewall.New(makeRng(1), nil)
	assert(#round.Packets == 20)
	local taps: { Firewall.Tap } = {}
	for _, packet in round.Packets do
		assert(packet.Lane >= 1 and packet.Lane <= 3)
		if packet.Red then
			table.insert(taps, { Id = packet.Id, At = packet.ArriveAt })
		end
	end
	local result = Firewall.Judge(round, taps)
	assert(result.Correct == 20 and result.Total == 20)
	assert(Firewall.Grade(result.Correct, result.Total) == "S")
end

tests["firewall late tap is missed"] = function()
	local round = Firewall.New(makeRng(2), nil)
	local red: Firewall.Packet? = nil
	for _, packet in round.Packets do
		if packet.Red then
			red = packet
			break
		end
	end
	assert(red, "seed produced no red packet")
	local onTime = Firewall.Judge(round, { { Id = red.Id, At = red.ArriveAt + 0.3 } })
	local late = Firewall.Judge(round, { { Id = red.Id, At = red.ArriveAt + 0.31 } })
	local none = Firewall.Judge(round, {})
	assert(onTime.Correct == none.Correct + 1)
	assert(late.Correct == none.Correct)
end

tests["firewall tapping a green packet is wrong"] = function()
	local round = Firewall.New(makeRng(3), nil)
	local green: Firewall.Packet? = nil
	for _, packet in round.Packets do
		if not packet.Red then
			green = packet
			break
		end
	end
	assert(green, "seed produced no green packet")
	local none = Firewall.Judge(round, {})
	local wrong = Firewall.Judge(round, { { Id = green.Id, At = green.ArriveAt } })
	assert(wrong.Correct == none.Correct - 1)
end

tests["triage short round for QA"] = function()
	local full = Triage.New(makeRng(4), { Bank = IncidentBanks.TRIAGE_REPORTS })
	local short = Triage.New(makeRng(4), { Short = true, Bank = IncidentBanks.TRIAGE_REPORTS })
	assert(#IncidentBanks.TRIAGE_REPORTS == 15)
	assert(#full.Reports == 10)
	assert(#short.Reports == 6)
	local answers: { [number]: string } = {}
	for _, report in short.Reports do
		answers[report.Id] = report.Answer
	end
	local result = Triage.Judge(short, answers)
	assert(result.Correct == 6 and result.Total == 6)
	assert(Triage.Judge(short, {}).Correct == 0)
end

tests["clap back shuffle keeps the best reply"] = function()
	assert(#IncidentBanks.CLAPBACK_POSTS == 10)
	for seed = 1, 20 do
		local round = ClapBack.New(makeRng(seed), { Bank = IncidentBanks.CLAPBACK_POSTS })
		assert(#round.Posts == 5)
		for _, post in round.Posts do
			assert(#post.Replies == 3)
			local bestText: string? = nil
			for _, entry in IncidentBanks.CLAPBACK_POSTS do
				if entry.Post == post.Post then
					bestText = entry.Replies[entry.Best]
				end
			end
			assert(bestText and post.Replies[post.Best] == bestText)
		end
	end
end

tests["clap back short for PR"] = function()
	local round = ClapBack.New(makeRng(5), { Short = true, Bank = IncidentBanks.CLAPBACK_POSTS })
	assert(#round.Posts == 3)
	local picks: { [number]: number } = {}
	for index, post in round.Posts do
		picks[index] = post.Best
	end
	assert(ClapBack.Judge(round, picks).Correct == 3)
	assert(ClapBack.Judge(round, {}).Correct == 0)
end

tests["grades follow thresholds"] = function()
	for _, module in { Firewall, Triage, ClapBack } do
		assert(module.Grade(19, 20) == "S")
		assert(module.Grade(16, 20) == "A")
		assert(module.Grade(12, 20) == "B")
		assert(module.Grade(5, 20) == "C")
		assert(module.Grade(0, 0) == "C")
	end
end

return tests
