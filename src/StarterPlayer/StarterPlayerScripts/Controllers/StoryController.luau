--!strict
-- Sibling texts as phone toasts, and the full-screen card when rent is paid and Act 1 ends.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local TEXT_SECONDS = 5

local StoryController = {}

local gui: ScreenGui
local toast: Frame
local toastText: TextLabel
local card: Frame
local cardBody: Frame
local toastToken = 0

local function showText(message: any)
	if type(message) ~= "string" then
		return
	end
	toastToken += 1
	local token = toastToken
	toastText.Text = message
	toast.Visible = true
	task.delay(TEXT_SECONDS, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

local function showCard(lines: { string }, ending: string)
	for _, child in cardBody:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, line in lines do
		Theme.Text(cardBody, line, 22).LayoutOrder = index
	end
	local endingLabel = Theme.Text(cardBody, ending, 30, Theme.ACCENT)
	endingLabel.LayoutOrder = #lines + 1
	local close = Theme.Button(cardBody, "Keep playing", 16)
	close.LayoutOrder = #lines + 2
	close.Activated:Connect(function()
		card.Visible = false
	end)
	card.Visible = true
end

local function onBeat(kind: any, payload: any)
	if kind == "SiblingText" then
		showText(payload)
	elseif kind == "RentPaid" and type(payload) == "table" then
		local lines: { string } = {}
		if type(payload.Lines) == "table" then
			for _, line in payload.Lines do
				if type(line) == "string" then
					table.insert(lines, line)
				end
			end
		end
		showCard(lines, tostring(payload.Ending))
	elseif kind == "Act1Complete" then
		showCard({}, tostring(payload))
	end
end

function StoryController.Init()
	gui = Theme.Screen("Story", 8)

	toast = Theme.Panel(gui, UDim2.fromOffset(300, 0), UDim2.new(1, -12, 0, 12))
	toast.AnchorPoint = Vector2.new(1, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.Visible = false
	Theme.List(toast, 4)
	Theme.Text(toast, "SIBLING  ·  new message", 12, Theme.MUTED).LayoutOrder = 1
	toastText = Theme.Text(toast, "", 16)
	toastText.LayoutOrder = 2

	card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Theme.BACKGROUND
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = gui

	cardBody = Instance.new("Frame")
	cardBody.BackgroundTransparency = 1
	cardBody.AnchorPoint = Vector2.new(0.5, 0.5)
	cardBody.Position = UDim2.fromScale(0.5, 0.5)
	cardBody.Size = UDim2.fromScale(0.6, 0.6)
	cardBody.Parent = card
	Theme.List(cardBody, 14)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function StoryController.Start()
	RemoteManager.GetRemote(RemoteNames.StoryBeat).OnClientEvent:Connect(onBeat)
end

return StoryController
