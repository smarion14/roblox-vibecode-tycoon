--!strict
-- Plot front doors slide open on this client when any character, or a local cutscene actor, walks up to them.
-- Doors are client-side so each player's own movement (and their cutscenes) never waits on the server.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CHECK_SECONDS = 0.1
local OPEN_DISTANCE = 9
local SLIDE_SECONDS = 0.35

local DoorController = {}

type DoorState = { Closed: CFrame, Open: boolean }
local doors: { [BasePart]: DoorState } = {}

local function walkerPositions(): { Vector3 }
	local positions: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	-- Cutscene actors are local models named Actor_<Kind> parented to Workspace.
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and string.sub(child.Name, 1, 6) == "Actor_" then
			table.insert(positions, child:GetPivot().Position)
		end
	end
	return positions
end

local function step()
	local positions = walkerPositions()
	for _, door in CollectionService:GetTagged("UnitDoor") do
		if not door:IsA("BasePart") then
			continue
		end
		local state = doors[door]
		if not state then
			state = { Closed = door.CFrame, Open = false }
			doors[door] = state
			door.Destroying:Once(function()
				doors[door] = nil
			end)
		end
		local near = false
		for _, position in positions do
			local offset = position - state.Closed.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= OPEN_DISTANCE then
				near = true
				break
			end
		end
		if near ~= state.Open then
			state.Open = near
			local slide = door:GetAttribute("SlideX")
			local target = if near then state.Closed * CFrame.new(if type(slide) == "number" then slide else 6, 0, 0) else state.Closed
			TweenService:Create(door, TweenInfo.new(SLIDE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
			door.CanCollide = not near
		end
	end
end

function DoorController.Init() end

function DoorController.Start()
	task.spawn(function()
		while true do
			step()
			task.wait(CHECK_SECONDS)
		end
	end)
end

return DoorController
