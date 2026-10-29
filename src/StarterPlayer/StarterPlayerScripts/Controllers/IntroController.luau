--!strict
-- Opening scene: the sibling's lines typed out terminal-style over a dark overlay, then Continue.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local CHAR_DELAY = 0.025
local LINE_PAUSE = 0.6

local IntroController = {}

local gui: ScreenGui
local body: Frame
local continueButton: TextButton
local skipping = false

local function typeLine(text: string, color: Color3)
	local label = Theme.Text(body, "", 22, color)
	label.LayoutOrder = #body:GetChildren()
	for i = 1, #text do
		if skipping then
			break
		end
		label.Text = string.sub(text, 1, i)
		task.wait(CHAR_DELAY)
	end
	label.Text = text
	if not skipping then
		task.wait(LINE_PAUSE)
	end
end

function IntroController.Play(lines: any)
	if type(lines) ~= "table" then
		return
	end
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	skipping = false
	continueButton.Text = "Skip"
	gui.Enabled = true

	for _, line in lines do
		if type(line) == "string" then
			-- Quoted dialogue stands out in the accent colour.
			local isSpeech = string.find(line, "That's not coding", 1, true) ~= nil
			typeLine(line, if isSpeech then Theme.ACCENT else Theme.TEXT)
		end
	end
	continueButton.Text = "Continue"
end

function IntroController.Init()
	gui = Theme.Screen("Intro", 10)
	gui.IgnoreGuiInset = true
	gui.Enabled = false

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.BACKGROUND
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.45)
	body.Size = UDim2.fromScale(0.6, 0.5)
	body.Parent = backdrop
	Theme.List(body, 14)

	continueButton = Theme.Button(backdrop, "Skip", 18)
	continueButton.AnchorPoint = Vector2.new(0.5, 1)
	continueButton.Position = UDim2.new(0.5, 0, 1, -60)
	continueButton.Size = UDim2.fromOffset(220, 44)
	continueButton.Activated:Connect(function()
		if continueButton.Text == "Skip" then
			skipping = true
			return
		end
		gui.Enabled = false
		RemoteManager.FireServer(RemoteNames.IntroSeen)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- StoryController owns the single StoryBeat listener and calls Play, so the queued intro beat can't be missed.
function IntroController.Start() end

return IntroController
