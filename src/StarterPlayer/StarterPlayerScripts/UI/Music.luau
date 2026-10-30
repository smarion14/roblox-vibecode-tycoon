--!strict
-- Client background music with crossfades, in its own "Music" SoundGroup (separate from SFX for a future volume slider).
-- Tracks come from the licensed APM / DistroKid catalogs on the Creator Store, which play in any experience.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

export type TrackName = "Battle" | "Boss"

type TrackDef = {
	Id: number,
	Volume: number,
}

local TRACKS: { [string]: TrackDef } = {
	Battle = { Id = 140486290054589, Volume = 0.35 }, -- "Insert Coin", synthwave
	Boss = { Id = 9038252619, Volume = 0.4 }, -- "Metal Sci-Fi Universe", driving lead synth
}
local DEFAULT_FADE = 1

local Music = {}

local group: SoundGroup? = nil
local sounds: { [string]: Sound } = {}
local current: Sound? = nil

local function ensureSounds()
	if group then
		return
	end
	local newGroup = Instance.new("SoundGroup")
	newGroup.Name = "Music"
	newGroup.Volume = 1
	newGroup.Parent = SoundService
	group = newGroup

	local all: { Instance } = {}
	for name, def in TRACKS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = `rbxassetid://{def.Id}`
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = newGroup
		sound.Parent = newGroup
		sounds[name] = sound
		table.insert(all, sound)
	end

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(all)
		end)
	end)
end

local function fadeOut(sound: Sound, seconds: number)
	local tween = TweenService:Create(sound, TweenInfo.new(seconds), { Volume = 0 })
	tween.Completed:Once(function()
		if sound ~= current then
			sound:Stop()
		end
	end)
	tween:Play()
end

-- Crossfades to the track; does nothing if it's already playing.
function Music.Play(name: TrackName, fadeSeconds: number?)
	ensureSounds()
	local sound = sounds[name]
	if not sound or sound == current then
		return
	end
	local seconds = fadeSeconds or DEFAULT_FADE
	local previous = current
	current = sound
	if previous then
		fadeOut(previous, seconds)
	end
	sound.TimePosition = 0
	sound.Volume = 0
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(seconds), { Volume = TRACKS[name].Volume }):Play()
end

function Music.Stop(fadeSeconds: number?)
	local previous = current
	current = nil
	if previous then
		fadeOut(previous, fadeSeconds or DEFAULT_FADE)
	end
end

function Music.Preload()
	ensureSounds()
end

return Music
