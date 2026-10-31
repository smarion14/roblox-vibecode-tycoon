--!strict
-- Holds the character still while the server says a minigame, burst or battle is running, so the keys those games
-- use (A/D, Space, arrows) don't also walk or jump the character. The server sets the player's "Activity" attribute.
local Players = game:GetService("Players")

local ActivityLockController = {}

local player = Players.LocalPlayer
local locked = false

local function apply()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return
	end
	local busy = player:GetAttribute("Activity") ~= nil and player:GetAttribute("Activity") ~= "Idle"
	-- A seated burst is already held by its seat; anchoring would fight the seat weld.
	local shouldLock = busy and not humanoid.Sit
	if shouldLock ~= locked then
		locked = shouldLock
		root.Anchored = shouldLock
	end
end

function ActivityLockController.Init() end

function ActivityLockController.Start()
	player:GetAttributeChangedSignal("Activity"):Connect(apply)
	player.CharacterAdded:Connect(function()
		locked = false
		apply()
	end)
	apply()
end

return ActivityLockController
