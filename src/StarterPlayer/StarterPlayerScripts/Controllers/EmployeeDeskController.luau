--!strict
-- Build progress bar on the screen of each of your employees' desks. The server owns the numbers and only
-- publishes them as desk attributes (Working, BuildProgress, PartsBuilt); this just draws them.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

local BAR_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
local POP_AMOUNT = 0.2
local OWN_UNIT_WAIT = 10
local POLL_SECONDS = 0.25
local GUI_NAME = "BuildBar"

local EmployeeDeskController = {}

local player = Players.LocalPlayer

local function unitIndexOf(desk: Instance): any
	local node: Instance? = desk
	while node and node:GetAttribute("Unit") == nil do
		node = node.Parent
	end
	return if node then node:GetAttribute("Unit") else nil
end

-- Waits for the player's unit index (it can land after the desks replicate); false when the desk is someone else's.
local function isOwnDesk(desk: Instance): boolean
	local deadline = os.clock() + OWN_UNIT_WAIT
	repeat
		local own = player:GetAttribute("Unit")
		local index = unitIndexOf(desk)
		if own ~= nil and index ~= nil then
			return own == index
		end
		task.wait(POLL_SECONDS)
	until os.clock() > deadline or not desk:IsDescendantOf(game)
	return false
end

local function buildBar(screen: BasePart): (SurfaceGui, Frame, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = GUI_NAME
	gui.Face = Enum.NormalId.Back
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.ZOffset = 1
	gui.Enabled = false
	gui.Parent = screen

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 0.92)
	track.Size = UDim2.fromScale(0.86, 0.14)
	track.BackgroundColor3 = Theme.BACKGROUND
	track.BorderSizePixel = 0
	track.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.TYPED
	stroke.Thickness = 1
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.TYPED
	fill.BorderSizePixel = 0
	fill.Parent = track
	return gui, track, fill
end

local function attach(desk: Instance)
	if not desk:IsA("BasePart") or not isOwnDesk(desk) then
		return
	end
	local link = desk:WaitForChild("Screen", OWN_UNIT_WAIT)
	local screen = if link and link:IsA("ObjectValue") then link.Value else nil
	if not screen or not screen:IsA("BasePart") or screen:FindFirstChild(GUI_NAME) then
		return
	end

	local gui, track, fill = buildBar(screen)
	local built = desk:GetAttribute("PartsBuilt")
	local lastBuilt: number = if type(built) == "number" then built else 0

	local function onProgress()
		local progress = desk:GetAttribute("BuildProgress")
		local target = if type(progress) == "number" then math.clamp(progress, 0, 1) else 0
		-- A finished part wraps the bar back to the start; snap instead of tweening backwards.
		if target < fill.Size.X.Scale then
			fill.Size = UDim2.fromScale(0, 1)
		end
		TweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(target, 1) }):Play()
	end
	local function onWorking()
		gui.Enabled = desk:GetAttribute("Working") == true
	end
	local function onBuilt()
		local count = desk:GetAttribute("PartsBuilt")
		if type(count) == "number" and count > lastBuilt then
			Juice.Pop(track, POP_AMOUNT)
			Sfx.Play("PartEarned")
		end
		lastBuilt = if type(count) == "number" then count else lastBuilt
	end

	desk:GetAttributeChangedSignal("BuildProgress"):Connect(onProgress)
	desk:GetAttributeChangedSignal("Working"):Connect(onWorking)
	desk:GetAttributeChangedSignal("PartsBuilt"):Connect(onBuilt)
	onProgress()
	onWorking()
end

function EmployeeDeskController.Init() end

function EmployeeDeskController.Start()
	CollectionService:GetInstanceAddedSignal("EmployeeDesk"):Connect(function(desk: Instance)
		task.spawn(attach, desk)
	end)
	for _, desk in CollectionService:GetTagged("EmployeeDesk") do
		task.spawn(attach, desk)
	end
end

return EmployeeDeskController
