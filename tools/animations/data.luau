--!strict
-- Hand-authored keyframes for the cutscene and employee animations. build.luau turns these into KeyframeSequences.
-- Rotations are degrees (x, y, z) applied at each part's joint, on the R15 rig. Parts not listed stay at rest.
-- Signs follow Roblox joint space: positive x on an upper arm or upper leg swings it forward.

export type Pose = { Rotation: { number } }
export type Keyframe = { Time: number, Poses: { [string]: Pose } }
export type Animation = { Looped: boolean, Keyframes: { Keyframe } }

local function r(x: number, y: number, z: number): Pose
	return { Rotation = { x, y, z } }
end

-- A seated lower body, shared by the couch and desk poses.
local function seated(poses: { [string]: Pose }): { [string]: Pose }
	poses.LeftUpperLeg = r(90, 0, 0)
	poses.RightUpperLeg = r(90, 0, 0)
	poses.LeftLowerLeg = r(-90, 0, 0)
	poses.RightLowerLeg = r(-90, 0, 0)
	return poses
end

return {
	-- The brother leans over the couch and shuts the laptop with one hand.
	LaptopClose = {
		Looped = false,
		Keyframes = {
			{ Time = 0, Poses = {} },
			{ Time = 0.4, Poses = { UpperTorso = r(-20, 0, 0), RightUpperArm = r(75, 0, 0), RightLowerArm = r(25, 0, 0), Head = r(-15, 0, 0) } },
			{ Time = 0.75, Poses = { UpperTorso = r(-25, 0, 0), RightUpperArm = r(35, 0, 0), RightLowerArm = r(10, 0, 0), Head = r(-20, 0, 0) } },
			{ Time = 1.2, Poses = {} },
		},
	},
	-- The player holds the rent out at arm's length.
	HandOverCash = {
		Looped = false,
		Keyframes = {
			{ Time = 0, Poses = {} },
			{ Time = 0.45, Poses = { RightUpperArm = r(80, 0, 0), RightLowerArm = r(10, 0, 0), Head = r(-5, 0, 0) } },
			{ Time = 1.1, Poses = { RightUpperArm = r(80, 0, 0), RightLowerArm = r(10, 0, 0), Head = r(-5, 0, 0) } },
			{ Time = 1.5, Poses = {} },
		},
	},
	-- The brother counts the bills twice, head down.
	CountCash = {
		Looped = false,
		Keyframes = {
			{ Time = 0, Poses = {} },
			{ Time = 0.3, Poses = { Head = r(-20, 0, 0), LeftUpperArm = r(45, 0, 0), LeftLowerArm = r(60, 0, 0), RightUpperArm = r(45, 0, 0), RightLowerArm = r(60, 0, 0) } },
			{ Time = 0.6, Poses = { Head = r(-20, 0, 0), LeftUpperArm = r(45, 0, 0), LeftLowerArm = r(60, 0, 0), RightUpperArm = r(45, 0, -10), RightLowerArm = r(75, 0, 0) } },
			{ Time = 0.9, Poses = { Head = r(-20, 0, 0), LeftUpperArm = r(45, 0, 0), LeftLowerArm = r(60, 0, 0), RightUpperArm = r(45, 0, 0), RightLowerArm = r(60, 0, 0) } },
			{ Time = 1.2, Poses = { Head = r(-20, 0, 0), LeftUpperArm = r(45, 0, 0), LeftLowerArm = r(60, 0, 0), RightUpperArm = r(45, 0, -10), RightLowerArm = r(75, 0, 0) } },
			{ Time = 1.5, Poses = { Head = r(-20, 0, 0), LeftUpperArm = r(45, 0, 0), LeftLowerArm = r(60, 0, 0), RightUpperArm = r(45, 0, 0), RightLowerArm = r(60, 0, 0) } },
			{ Time = 2, Poses = {} },
		},
	},
	-- Idle talking: a small nod and an open-hand gesture.
	Talk = {
		Looped = true,
		Keyframes = {
			{ Time = 0, Poses = {} },
			{ Time = 0.5, Poses = { Head = r(8, 0, 0), RightUpperArm = r(30, 0, 10), RightLowerArm = r(40, 0, 0) } },
			{ Time = 1, Poses = { Head = r(-4, 5, 0), RightUpperArm = r(20, 0, 15), RightLowerArm = r(30, 0, 0) } },
			{ Time = 1.5, Poses = { Head = r(6, -5, 0) } },
			{ Time = 2, Poses = {} },
		},
	},
	-- Slumped on the couch with the laptop on the knees.
	SitCouch = {
		Looped = true,
		Keyframes = {
			{ Time = 0, Poses = seated({ UpperTorso = r(-8, 0, 0), Head = r(-15, 0, 0), LeftUpperArm = r(35, 0, 0), RightUpperArm = r(35, 0, 0), LeftLowerArm = r(40, 0, 0), RightLowerArm = r(40, 0, 0) }) },
			{ Time = 1.5, Poses = seated({ UpperTorso = r(-10, 0, 0), Head = r(-18, 0, 0), LeftUpperArm = r(35, 0, 0), RightUpperArm = r(35, 0, 0), LeftLowerArm = r(42, 0, 0), RightLowerArm = r(42, 0, 0) }) },
			{ Time = 3, Poses = seated({ UpperTorso = r(-8, 0, 0), Head = r(-15, 0, 0), LeftUpperArm = r(35, 0, 0), RightUpperArm = r(35, 0, 0), LeftLowerArm = r(40, 0, 0), RightLowerArm = r(40, 0, 0) }) },
		},
	},
	-- An employee seated at a desk, typing with alternating hands.
	DeskType = {
		Looped = true,
		Keyframes = {
			{ Time = 0, Poses = seated({ Head = r(-8, 0, 0), LeftUpperArm = r(55, 0, 0), RightUpperArm = r(55, 0, 0), LeftLowerArm = r(35, 0, 0), RightLowerArm = r(35, 0, 0) }) },
			{ Time = 0.25, Poses = seated({ Head = r(-8, 0, 0), LeftUpperArm = r(55, 0, 0), RightUpperArm = r(55, 0, 0), LeftLowerArm = r(42, 0, 0), RightLowerArm = r(30, 0, 0) }) },
			{ Time = 0.5, Poses = seated({ Head = r(-8, 0, 0), LeftUpperArm = r(55, 0, 0), RightUpperArm = r(55, 0, 0), LeftLowerArm = r(30, 0, 0), RightLowerArm = r(42, 0, 0) }) },
			{ Time = 0.75, Poses = seated({ Head = r(-8, 0, 0), LeftUpperArm = r(55, 0, 0), RightUpperArm = r(55, 0, 0), LeftLowerArm = r(42, 0, 0), RightLowerArm = r(30, 0, 0) }) },
			{ Time = 1, Poses = seated({ Head = r(-8, 0, 0), LeftUpperArm = r(55, 0, 0), RightUpperArm = r(55, 0, 0), LeftLowerArm = r(35, 0, 0), RightLowerArm = r(35, 0, 0) }) },
		},
	},
} :: { [string]: Animation }
