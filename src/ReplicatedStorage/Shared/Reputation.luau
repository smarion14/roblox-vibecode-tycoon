--!strict
-- Pure: no requires, no Roblox APIs. Act 3 reputation (0-100) and its payout multiplier.

local MAX_REPUTATION = 100

local Reputation = {}

-- Linear from minM at 0 reputation to maxM at 100; out-of-range input clamps.
function Reputation.Multiplier(rep: number, minM: number, maxM: number): number
	return minM + (maxM - minM) * math.clamp(rep, 0, MAX_REPUTATION) / MAX_REPUTATION
end

function Reputation.Apply(rep: number, delta: number): number
	return math.clamp(rep + delta, 0, MAX_REPUTATION)
end

return Reputation
