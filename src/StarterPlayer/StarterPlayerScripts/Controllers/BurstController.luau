--!strict
-- Station burst panel: prompt, draining timer and the grade popup. The server sends each prompt and the grade.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Theme = require(UI:WaitForChild("Theme"))
local TypingInput = require(UI:WaitForChild("TypingInput"))

local GRADE_POPUP_SECONDS = 1.5

local BurstController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local previewLabel: TextLabel
local timerFill: Frame
local timerBar: Frame
local secondsLabel: TextLabel
local deadline = 0
local maxSeconds = 1
local countdown: RBXScriptConnection? = nil
local gradeLabel: TextLabel
local field: TypingInput.TypingField? = nil
local currentIndex = 0
local timerTween: Tween? = nil

local function closeField()
	if field then
		field:Destroy()
		field = nil
	end
	if countdown then
		countdown:Disconnect()
		countdown = nil
	end
end

-- Restarts the bar from the server's remaining time. The bar's full width is the most time seen this burst,
-- so earned bonus time visibly refills it.
local function startTimer(seconds: number)
	if timerTween then
		timerTween:Cancel()
	end
	maxSeconds = math.max(maxSeconds, seconds)
	deadline = os.clock() + seconds
	timerFill.Size = UDim2.fromScale(seconds / maxSeconds, 1)
	local tween = TweenService:Create(timerFill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(0, 1),
	})
	tween:Play()
	timerTween = tween
end

local function onPrompt(index: any, text: any, nextText: any, timeLeft: any, timeDelta: any)
	if type(index) ~= "number" or type(text) ~= "string" then
		return
	end
	currentIndex = index

	if index == 1 then
		closeField()
		gradeLabel.Visible = false
		local newField = TypingInput.Create(panel, TypingInput.DetectMode())
		newField.OnSubmit = function(typed: string)
			RemoteManager.FireServer(RemoteNames.SubmitBurstPrompt, currentIndex, typed)
		end
		field = newField

		maxSeconds = 1
		countdown = RunService.RenderStepped:Connect(function()
			secondsLabel.Text = string.format("%.1fs", math.max(deadline - os.clock(), 0))
		end)
		gui.Enabled = true
	end

	startTimer(if type(timeLeft) == "number" then math.max(timeLeft, 0) else 0)
	if type(timeDelta) == "number" and math.abs(timeDelta) > 0.01 then
		local gained = timeDelta > 0
		local deltaText = if gained then string.format("+%gs", timeDelta) else string.format("%gs", timeDelta)
		Juice.FloatText(timerBar, UDim2.fromScale(1, -1), deltaText, if gained then Theme.TYPED else Theme.BUG)
		if gained then
			Juice.Pop(secondsLabel, 0.4)
		else
			Juice.Shake(secondsLabel, nil)
		end
	end

	header.Text = `PROMPT {index}`
	previewLabel.Text = if type(nextText) == "string" then `next: {nextText}` else ""
	if field then
		field:SetPrompt(text)
	end
end

local function onFinished(grade: any, accuracy: any)
	closeField()
	if timerTween then
		timerTween:Cancel()
	end
	local percent = if type(accuracy) == "number" then math.floor(accuracy * 100 + 0.5) else 0
	gradeLabel.Text = `{tostring(grade)}   {percent}%`
	gradeLabel.Visible = true
	task.delay(GRADE_POPUP_SECONDS, function()
		if not field then
			gui.Enabled = false
		end
	end)
end

function BurstController.Init()
	gui = Theme.Screen("Burst", 4)
	gui.Enabled = false

	panel = Theme.Panel(gui, UDim2.fromOffset(640, 0), UDim2.new(0.5, 0, 1, -40))
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(panel, 8)

	header = Theme.Text(panel, "", 14, Theme.MUTED)
	header.LayoutOrder = -3

	secondsLabel = Theme.Text(header, "", 14, Theme.ACCENT)
	secondsLabel.AnchorPoint = Vector2.new(1, 0)
	secondsLabel.Position = UDim2.fromScale(1, 0)
	secondsLabel.Size = UDim2.fromOffset(80, 18)
	secondsLabel.AutomaticSize = Enum.AutomaticSize.None
	secondsLabel.TextXAlignment = Enum.TextXAlignment.Right

	timerBar = Instance.new("Frame")
	timerBar.Size = UDim2.new(1, 0, 0, 8)
	timerBar.BackgroundColor3 = Theme.PANEL
	timerBar.BorderSizePixel = 0
	timerBar.LayoutOrder = -2
	timerBar.Parent = panel
	timerFill = Instance.new("Frame")
	timerFill.BackgroundColor3 = Theme.ACCENT
	timerFill.BorderSizePixel = 0
	timerFill.Parent = timerBar

	previewLabel = Theme.Text(panel, "", 13, Theme.TODO)
	previewLabel.LayoutOrder = 10

	gradeLabel = Theme.Text(panel, "", 36, Theme.TYPED)
	gradeLabel.TextXAlignment = Enum.TextXAlignment.Center
	gradeLabel.LayoutOrder = 11
	gradeLabel.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function BurstController.Start()
	RemoteManager.GetRemote(RemoteNames.BurstPrompt).OnClientEvent:Connect(onPrompt)
	RemoteManager.GetRemote(RemoteNames.BurstFinished).OnClientEvent:Connect(onFinished)
end

return BurstController
