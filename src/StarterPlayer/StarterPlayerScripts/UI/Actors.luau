--!strict
-- Client-local actor rigs for cutscenes (and employee NPC animation): copies of the player and the brother,
-- placed on floor-level marker CFrames, animated with published ids or a built-in fallback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

export type ActorKind = "Player" | "Brother"

-- Roblox's default R15 animations, used until a custom one is published.
local WALK_ID = 507777826
local FALLBACK_IDS: { [string]: number } = {
	SitCouch = 2506281703, -- sit
	DeskType = 2506281703, -- sit
	Talk = 507766388, -- idle
}

local Actors = {}

local function rootOf(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Marker CFrames sit on the floor; a rig's root sits hip height plus half its own height above that.
local function rootOffset(model: Model): CFrame
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = rootOf(model)
	local height = (if humanoid then humanoid.HipHeight else 2) + (if root then root.Size.Y / 2 else 1)
	return CFrame.new(0, height, 0)
end

local function animatorOf(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	return animator
end

local function playId(model: Model, id: number, looped: boolean?): AnimationTrack?
	local animator = animatorOf(model)
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{id}`
	local ok, track = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	if looped ~= nil then
		track.Looped = looped
	end
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	return track
end

local function source(kind: ActorKind): Model?
	if kind == "Player" then
		return Players.LocalPlayer.Character
	end
	local index = Players.LocalPlayer:GetAttribute("Unit")
	for _, unit in Workspace:WaitForChild("Megablock"):GetChildren() do
		if unit:GetAttribute("Unit") == index then
			local sibling = unit:FindFirstChild("SiblingModel", true)
			if sibling and sibling:IsA("Model") then
				return sibling
			end
		end
	end
	return ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("BrotherTemplate") :: Model?
end

-- A local copy standing on a floor-level CFrame. The root is anchored and moved by tweens; the body follows
-- through its joints, so animations still play.
function Actors.Spawn(kind: ActorKind, at: CFrame): Model?
	local original = source(kind)
	if not original then
		return nil
	end
	local wasArchivable = original.Archivable
	original.Archivable = true
	local copy = original:Clone()
	original.Archivable = wasArchivable
	if not copy then
		return nil
	end
	copy.Name = `Actor_{kind}`
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = descendant.Name == "HumanoidRootPart"
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.LocalTransparencyModifier = 0
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	copy.Parent = Workspace
	local root = rootOf(copy)
	if root then
		root.CFrame = at * rootOffset(copy)
	end
	return copy
end

-- Plays a named animation: the published id when set, else a built-in fallback, else nothing.
function Actors.Play(model: Model, animation: string): AnimationTrack?
	local id = GameConfig.ANIMATIONS[animation]
	if id and id ~= 0 then
		return playId(model, id)
	end
	local fallback = FALLBACK_IDS[animation]
	return if fallback then playId(model, fallback, true) else nil
end

function Actors.StopAll(model: Model)
	local animator = animatorOf(model)
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0.2)
		end
	end
end

-- Turns to face the destination, walks there over `seconds` with the walk cycle, then takes the marker's facing.
-- Yields until the walk is done.
function Actors.WalkTo(model: Model, to: CFrame, seconds: number)
	local root = rootOf(model)
	if not root then
		return
	end
	Actors.StopAll(model)
	local target = to * rootOffset(model)
	local from = root.Position
	if (target.Position - from).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(from, Vector3.new(target.X, from.Y, target.Z))
	end
	local walk = playId(model, WALK_ID, true)
	local tween = TweenService:Create(root, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(target.Position, target.Position + root.CFrame.LookVector),
	})
	tween:Play()
	tween.Completed:Wait()
	if walk then
		walk:Stop(0.2)
	end
	root.CFrame = target
end

function Actors.Place(model: Model, at: CFrame)
	local root = rootOf(model)
	if root then
		root.CFrame = at * rootOffset(model)
	end
end

return Actors
