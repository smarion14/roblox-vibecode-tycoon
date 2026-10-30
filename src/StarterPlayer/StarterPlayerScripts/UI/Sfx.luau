--!strict
-- Client sound effects. Every sound is a pooled, preloaded Sound in one "SFX" SoundGroup (ready for a volume slider).
-- Sounds are Pro Sound Effects / Roblox uploads from the Creator Store, which play in any experience.
-- Swap an id here to change a sound everywhere.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

export type SoundName =
	"KeyClick"
	| "KeyWrong"
	| "ChipTap"
	| "PromptClean"
	| "Splat"
	| "BossHit"
	| "BossDown"
	| "BugGotThrough"
	| "ComboCallout"
	| "Banner"
	| "Shipped"
	| "GradeStamp"
	| "GradeS"
	| "GradeSCash"
	| "GradeA"
	| "GradeB"
	| "GradeC"
	| "PartEarned"
	| "CardOpen"
	| "CardClose"

type SoundDef = {
	Ids: { number },
	Volume: number,
	PitchMin: number,
	PitchMax: number,
	Voices: number, -- copies per id so rapid repeats overlap instead of cutting each other off
}

local SOUNDS: { [string]: SoundDef } = {
	-- Round-robin through four different key recordings with a little pitch drift, so typing never sounds looped.
	KeyClick = { Ids = { 9116158538, 9113146359, 9113141689, 9116158128 }, Volume = 0.55, PitchMin = 0.94, PitchMax = 1.1, Voices = 3 },
	KeyWrong = { Ids = { 9118616650 }, Volume = 0.45, PitchMin = 1.3, PitchMax = 1.4, Voices = 3 },
	ChipTap = { Ids = { 15675059323 }, Volume = 0.5, PitchMin = 0.95, PitchMax = 1.1, Voices = 3 },
	PromptClean = { Ids = { 9116394545 }, Volume = 0.45, PitchMin = 1, PitchMax = 1.06, Voices = 2 },
	Splat = { Ids = { 12222152, 9120590649 }, Volume = 0.6, PitchMin = 0.9, PitchMax = 1.15, Voices = 3 },
	BossHit = { Ids = { 9113564874 }, Volume = 0.7, PitchMin = 0.85, PitchMax = 1, Voices = 2 },
	BossDown = { Ids = { 9114614607 }, Volume = 0.75, PitchMin = 0.95, PitchMax = 1, Voices = 1 },
	BugGotThrough = { Ids = { 9118616114 }, Volume = 0.7, PitchMin = 0.7, PitchMax = 0.8, Voices = 2 },
	ComboCallout = { Ids = { 9116395089 }, Volume = 0.5, PitchMin = 1.05, PitchMax = 1.15, Voices = 1 },
	Banner = { Ids = { 15674975792 }, Volume = 0.45, PitchMin = 1, PitchMax = 1, Voices = 1 },
	Shipped = { Ids = { 9116395085 }, Volume = 0.6, PitchMin = 1, PitchMax = 1, Voices = 1 },
	-- Burst grade reveal: a rubber-stamp slam on every grade, then a stinger that gets brighter with the grade.
	GradeStamp = { Ids = { 9114026047 }, Volume = 0.7, PitchMin = 0.95, PitchMax = 1.05, Voices = 1 },
	GradeS = { Ids = { 9126073011 }, Volume = 0.6, PitchMin = 1.05, PitchMax = 1.05, Voices = 1 },
	GradeSCash = { Ids = { 9113728042 }, Volume = 0.45, PitchMin = 1, PitchMax = 1, Voices = 1 },
	GradeA = { Ids = { 9126073001 }, Volume = 0.55, PitchMin = 1, PitchMax = 1, Voices = 1 },
	GradeB = { Ids = { 9126073026 }, Volume = 0.45, PitchMin = 0.85, PitchMax = 0.85, Voices = 1 },
	GradeC = { Ids = { 9119071955 }, Volume = 0.4, PitchMin = 0.75, PitchMax = 0.75, Voices = 1 },
	PartEarned = { Ids = { 15674975792 }, Volume = 0.4, PitchMin = 1.3, PitchMax = 1.4, Voices = 1 },
	-- Result cards: a low whoosh as a card slams in, a short high one as it closes.
	CardOpen = { Ids = { 15674975792 }, Volume = 0.5, PitchMin = 0.8, PitchMax = 0.85, Voices = 1 },
	CardClose = { Ids = { 15674975792 }, Volume = 0.3, PitchMin = 1.5, PitchMax = 1.6, Voices = 1 },
}

local Sfx = {}

local group: SoundGroup? = nil
local pools: { [string]: { Sound } } = {}
local cursors: { [string]: number } = {}
local rng = Random.new()

local function ensurePools()
	if group then
		return
	end
	local newGroup = Instance.new("SoundGroup")
	newGroup.Name = "SFX"
	newGroup.Volume = 1
	newGroup.Parent = SoundService
	group = newGroup

	local all: { Instance } = {}
	for name, def in SOUNDS do
		local pool: { Sound } = {}
		-- Interleave ids so consecutive plays alternate recordings.
		for _ = 1, def.Voices do
			for _, id in def.Ids do
				local sound = Instance.new("Sound")
				sound.Name = name
				sound.SoundId = `rbxassetid://{id}`
				sound.Volume = def.Volume
				sound.SoundGroup = newGroup
				sound.Parent = newGroup
				table.insert(pool, sound)
				table.insert(all, sound)
			end
		end
		pools[name] = pool
		cursors[name] = 0
	end

	-- Preload so the first keystroke isn't silent while the asset downloads.
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(all)
		end)
	end)
end

function Sfx.Play(name: SoundName)
	ensurePools()
	local pool = pools[name]
	local def = SOUNDS[name]
	if not pool or #pool == 0 then
		return
	end
	local cursor = cursors[name] % #pool + 1
	cursors[name] = cursor
	local sound = pool[cursor]
	sound.PlaybackSpeed = rng:NextNumber(def.PitchMin, def.PitchMax)
	sound.TimePosition = 0
	sound:Play()
end

-- Optional warm-up so preloading starts before the first sound is needed.
function Sfx.Preload()
	ensurePools()
end

return Sfx
