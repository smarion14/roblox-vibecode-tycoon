--!strict
-- Pure: no requires, no Roblox APIs. AI Model Rig minigame: a loss needle swings across a bar and the player
-- presses when it is inside the green zone. Each epoch the needle speeds up and the zone shrinks.

export type Epoch = {
	Speed: number, -- full swings per second
	Phase: number, -- radians
	ZoneCenter: number, -- 0-1 along the bar
	ZoneWidth: number, -- 0-1
}

export type Hit = "Perfect" | "Good" | "Miss"

local HIT_VALUE: { [Hit]: number } = { Perfect = 1, Good = 0.7, Miss = 0 }

local TrainingRun = {}

-- Needle position (0-1) at a time offset (seconds) since the epoch started.
function TrainingRun.NeedleAt(epoch: Epoch, offset: number): number
	return 0.5 + 0.5 * math.sin(2 * math.pi * epoch.Speed * offset + epoch.Phase)
end

-- Perfect inside the middle half of the zone, Good anywhere else in it, Miss outside.
function TrainingRun.JudgePress(epoch: Epoch, offset: number): Hit
	local distance = math.abs(TrainingRun.NeedleAt(epoch, offset) - epoch.ZoneCenter)
	if distance <= epoch.ZoneWidth / 4 then
		return "Perfect"
	elseif distance <= epoch.ZoneWidth / 2 then
		return "Good"
	end
	return "Miss"
end

function TrainingRun.Value(hit: Hit): number
	return HIT_VALUE[hit]
end

-- The client reports when it pressed (seconds since it was shown the epoch). The server only accepts a claim
-- that fits its own clock: no later than it actually arrived, and no earlier than the allowed network lag.
-- shortcut: a cheater can still pick the best moment inside the lag window; shrink maxLag if that matters.
function TrainingRun.IsPlausibleOffset(claimed: number, serverElapsed: number, maxLag: number, lead: number): boolean
	return claimed >= 0 and claimed <= serverElapsed + lead and claimed >= serverElapsed - maxLag
end

return TrainingRun
