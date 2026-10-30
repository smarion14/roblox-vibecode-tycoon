--!strict
-- Writes one KeyframeSequence .rbxm per animation in data.luau into src/ServerStorage/Animations, where Rojo
-- syncs them into Studio for publishing (see docs/animations-publish-checklist.md).
-- Run: lune run tools/animations/build.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local AnimationData = require("./data")

local Instance = roblox.Instance
local CFrame = roblox.CFrame

local OUT_DIR = "src/ServerStorage/Animations"

-- R15 joint tree: each part's pose sits under its parent part's pose.
local CHILDREN: { [string]: { string } } = {
	HumanoidRootPart = { "LowerTorso" },
	LowerTorso = { "UpperTorso", "LeftUpperLeg", "RightUpperLeg" },
	UpperTorso = { "Head", "LeftUpperArm", "RightUpperArm" },
	LeftUpperArm = { "LeftLowerArm" },
	LeftLowerArm = { "LeftHand" },
	RightUpperArm = { "RightLowerArm" },
	RightLowerArm = { "RightHand" },
	LeftUpperLeg = { "LeftLowerLeg" },
	LeftLowerLeg = { "LeftFoot" },
	RightUpperLeg = { "RightLowerLeg" },
	RightLowerLeg = { "RightFoot" },
}

local function buildPose(name: string, poses: { [string]: AnimationData.Pose }, parent: any)
	local pose = Instance.new("Pose")
	pose.Name = name
	local rotation = poses[name]
	pose.CFrame = if rotation
		then CFrame.Angles(math.rad(rotation.Rotation[1]), math.rad(rotation.Rotation[2]), math.rad(rotation.Rotation[3]))
		else CFrame.identity
	pose.Parent = parent
	for _, child in CHILDREN[name] or {} do
		buildPose(child, poses, pose)
	end
end

fs.writeDir(OUT_DIR)
local count = 0
for name, animation in AnimationData do
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = animation.Looped
	sequence.Priority = roblox.Enum.AnimationPriority.Action
	for _, keyframe in animation.Keyframes do
		local frame = Instance.new("Keyframe")
		frame.Time = keyframe.Time
		frame.Parent = sequence
		buildPose("HumanoidRootPart", keyframe.Poses, frame)
	end
	fs.writeFile(`{OUT_DIR}/{name}.rbxm`, roblox.serializeModel({ sequence }))
	count += 1
end
print(`wrote {count} animations to {OUT_DIR}`)
