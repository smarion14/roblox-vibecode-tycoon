--!strict
local AnimationData = require("../tools/animations/data")
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")

local R15_PARTS = {
	LowerTorso = true,
	UpperTorso = true,
	Head = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

local tests = {}

tests["every animation has increasing keyframe times starting at 0"] = function()
	for name, animation in AnimationData do
		assert(#animation.Keyframes >= 2, `{name}: needs at least two keyframes`)
		assert(animation.Keyframes[1].Time == 0, `{name}: first keyframe must be at 0`)
		for index = 2, #animation.Keyframes do
			assert(animation.Keyframes[index].Time > animation.Keyframes[index - 1].Time, `{name}: keyframe {index} goes back in time`)
		end
	end
end

tests["every pose names an R15 part"] = function()
	for name, animation in AnimationData do
		for _, keyframe in animation.Keyframes do
			for partName, pose in keyframe.Poses do
				assert(R15_PARTS[partName], `{name}: {partName} is not an R15 part`)
				assert(#pose.Rotation == 3, `{name}: {partName} rotation needs x, y, z`)
			end
		end
	end
end

tests["the set matches GameConfig.ANIMATIONS keys"] = function()
	for name in GameConfig.ANIMATIONS do
		assert(AnimationData[name], `missing animation data for {name}`)
	end
	for name in AnimationData do
		assert(GameConfig.ANIMATIONS[name] ~= nil, `{name} has no GameConfig.ANIMATIONS entry`)
	end
end

return tests
