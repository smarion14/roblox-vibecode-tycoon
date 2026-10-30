--!strict
-- Pure: no requires, no Roblox APIs. Database Console minigame: the NAS drive bays flash a sequence and the
-- player repeats it. Each round adds one more step. A wrong bay ends the game.

export type RoundResult = { Correct: number, Perfect: boolean }

local RaidRebuild = {}

function RaidRebuild.Generate(bays: number, length: number, rng: () -> number): { number }
	local sequence: { number } = {}
	for i = 1, length do
		local bay = math.clamp(1 + math.floor(rng() * bays), 1, bays)
		-- Avoid three of the same bay in a row: it reads as one long flash.
		if i > 2 and bay == sequence[i - 1] and bay == sequence[i - 2] then
			bay = bay % bays + 1
		end
		sequence[i] = bay
	end
	return sequence
end

-- Correct counts matching inputs before the first mistake; Perfect when the whole round was entered right.
function RaidRebuild.JudgeRound(sequence: { number }, roundLength: number, inputs: { any }): RoundResult
	local correct = 0
	for i = 1, roundLength do
		if inputs[i] ~= sequence[i] then
			break
		end
		correct += 1
	end
	return { Correct = correct, Perfect = correct == roundLength and #inputs == roundLength }
end

-- The answer can't arrive before the flash ends, nor faster than a human can tap the bays.
function RaidRebuild.IsPlausible(flashEndsAt: number, receivedAt: number, inputCount: number, minSecondsPerInput: number): boolean
	return receivedAt >= flashEndsAt + inputCount * minSecondsPerInput
end

return RaidRebuild
