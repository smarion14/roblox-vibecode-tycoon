--!strict
-- Sibling texts as phone toasts, cutscene beats handed to CutsceneController (story scenes and the finale replay from
-- the startup sign), milestone banners and the Act 2 tutorial pages.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))
local StoryText = require(Shared:WaitForChild("StoryText"))
local CutsceneController = require(script.Parent:WaitForChild("CutsceneController"))
local NameDialog = require(UI:WaitForChild("NameDialog"))

local TEXT_SECONDS = 5
-- The deploy that ends an act sends its scene before the battle's results; hold it while these are up (capped).
local BATTLE_GUIS = { "Battle", "BulletHell", "Results" }
local SCENE_HOLD_SECONDS = 15

local StoryController = {}

local gui: ScreenGui
local toast: Frame
local toastText: TextLabel
local card: Frame
local cardBody: Frame
local toastToken = 0
local bannerLayer: Frame
local milestoneBody: TextLabel
local milestoneQueue: { { Title: string, Body: string } } = {}
local milestoneWorker = false
local scenesHeld = 0

local function showText(message: any)
	if type(message) ~= "string" then
		return
	end
	toastToken += 1
	local token = toastToken
	toastText.Text = message
	-- Phone buzz: slides in from the right edge with a tap.
	Sfx.Play("ChipTap")
	Juice.SlideIn(toast, UDim2.fromOffset(340, 0))
	task.delay(TEXT_SECONDS, function()
		if toastToken == token then
			Juice.SlideOut(toast, UDim2.fromOffset(340, 0))
		end
	end)
end

-- A milestone gets a banner slam and its line floating up underneath. Several at once play one after another, and
-- any that arrive with a cutscene (e.g. the deploy that ends an act) wait until it ends, since this gui is hidden then.
local function showMilestone(payload: any)
	if type(payload) ~= "table" or type(payload.Title) ~= "string" or type(payload.Body) ~= "string" then
		return
	end
	table.insert(milestoneQueue, { Title = payload.Title, Body = payload.Body })
	if milestoneWorker then
		return
	end
	milestoneWorker = true
	task.spawn(function()
		task.wait(0.5) -- a cutscene sent with the same deploy gets to start first
		while #milestoneQueue > 0 do
			while scenesHeld > 0 or CutsceneController.IsPlaying() do
				task.wait(0.25)
			end
			local milestone = table.remove(milestoneQueue, 1) :: { Title: string, Body: string }
			Juice.Banner(bannerLayer, milestone.Title, Theme.MOOD, 40)
			Sfx.Play("Banner")
			milestoneBody.Text = milestone.Body
			milestoneBody.Visible = true
			Juice.PopIn(milestoneBody)
			task.wait(2.4)
			milestoneBody.Visible = false
			task.wait(0.2)
		end
		milestoneWorker = false
	end)
end

-- A paged card: heading, body, then Next (or "Let's go" on the last page).
local function showPages(pages: { { Title: string, Body: string } }, index: number)
	local page = pages[index]
	if not page then
		card.Visible = false
		return
	end
	for _, child in cardBody:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	Theme.Text(cardBody, `{index} / {#pages}`, 14, Theme.MUTED).LayoutOrder = 1
	Theme.Text(cardBody, page.Title, 30, Theme.ACCENT).LayoutOrder = 2
	Theme.Text(cardBody, page.Body, 22).LayoutOrder = 3
	local nextButton = Theme.Button(cardBody, if index == #pages then "Let's go" else "Next", 16)
	nextButton.LayoutOrder = 4
	nextButton.Activated:Connect(function()
		showPages(pages, index + 1)
	end)
	card.Visible = true
	Sfx.Play(if index == 1 then "Banner" else "ChipTap")
	Juice.PopIn(cardBody)
end

local function battleScreenOpen(): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	for _, name in BATTLE_GUIS do
		local screen = playerGui:FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") and screen.Enabled then
			return true
		end
	end
	return false
end

local function playScene(payload: any)
	local heldUntil = os.clock() + SCENE_HOLD_SECONDS
	scenesHeld += 1
	while battleScreenOpen() and os.clock() < heldUntil do
		task.wait(0.25)
	end
	scenesHeld -= 1
	CutsceneController.Play(payload)
end

local function onBeat(kind: any, payload: any)
	if kind == "Cutscene" then
		task.spawn(playScene, payload)
	elseif kind == "SiblingText" then
		showText(payload)
	elseif kind == "Milestone" then
		showMilestone(payload)
	elseif kind == "Act2Tutorial" then
		showPages(StoryText.ACT2_TUTORIAL, 1)
	end
end

function StoryController.Init()
	gui = Theme.Screen("Story", 8)

	bannerLayer = Instance.new("Frame")
	bannerLayer.Size = UDim2.fromScale(1, 1)
	bannerLayer.BackgroundTransparency = 1
	bannerLayer.Parent = gui
	milestoneBody = Theme.Text(bannerLayer, "", 20)
	milestoneBody.AutomaticSize = Enum.AutomaticSize.None
	milestoneBody.Size = UDim2.new(1, 0, 0, 28)
	milestoneBody.AnchorPoint = Vector2.new(0.5, 0.5)
	milestoneBody.Position = UDim2.fromScale(0.5, 0.5)
	milestoneBody.TextXAlignment = Enum.TextXAlignment.Center
	milestoneBody.TextStrokeTransparency = 0.4
	milestoneBody.Visible = false

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
	-- The office's startup sign reopens the naming dialog.
	RemoteManager.GetRemote(RemoteNames.OpenUI).OnClientEvent:Connect(function(kind: any, payload: any)
		if kind == "Rename" then
			task.spawn(NameDialog.Prompt, if type(payload) == "string" then payload else "", true)
		end
	end)
end

return StoryController
