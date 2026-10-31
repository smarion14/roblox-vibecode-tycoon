--!strict
-- Pure: no requires, no Roblox APIs. Firewall incident minigame: packets stream down three lanes; tap the red
-- (hostile) ones as they arrive and leave the green ones alone. The server judges taps against ArriveAt.

export type Grade = "S" | "A" | "B" | "C"
export type Packet = { Id: number, Red: boolean, Lane: number, ArriveAt: number }
export type Round = { Packets: { Packet } }
export type Tap = { Id: number, At: number } -- At: seconds since the round started, measured by the server
export type Result = { Correct: number, Total: number }

local Firewall = {}

local PACKET_COUNT = 20
local PACKET_GAP = 1 -- seconds between arrivals
local FIRST_ARRIVAL = 2
local RED_CHANCE = 0.4
local LANES = 3
local TAP_GRACE = 0.3 -- a tap later than ArriveAt + this is a miss

function Firewall.New(rng: () -> number, options: { [string]: any }?): Round
	local packets: { Packet } = {}
	for id = 1, PACKET_COUNT do
		table.insert(packets, {
			Id = id,
			Red = rng() < RED_CHANCE,
			Lane = math.min(LANES, math.floor(rng() * LANES) + 1),
			ArriveAt = FIRST_ARRIVAL + (id - 1) * PACKET_GAP,
		})
	end
	return { Packets = packets }
end

-- inputs is client data: ignore anything malformed. Only the first on-time tap per packet counts.
function Firewall.Judge(round: Round, inputs: { Tap }): Result
	local tapped: { [number]: boolean } = {}
	if type(inputs) == "table" then
		for _, tap in inputs do
			if type(tap) ~= "table" or type(tap.Id) ~= "number" or type(tap.At) ~= "number" then
				continue
			end
			local packet = round.Packets[tap.Id]
			if packet and tap.At == tap.At and tap.At <= packet.ArriveAt + TAP_GRACE then
				tapped[tap.Id] = true
			end
		end
	end
	local correct = 0
	for _, packet in round.Packets do
		if (tapped[packet.Id] == true) == packet.Red then
			correct += 1
		end
	end
	return { Correct = correct, Total = #round.Packets }
end

-- shortcut: Grade duplicated in Firewall/Triage/ClapBack (pure modules cannot require each other), keep thresholds in sync.
function Firewall.Grade(correct: number, total: number): Grade
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

return Firewall
