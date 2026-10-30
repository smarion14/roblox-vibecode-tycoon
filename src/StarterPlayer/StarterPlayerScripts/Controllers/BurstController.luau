--!strict
-- Station burst panel: prompt, draining timer and the grade popup. The server sends each prompt and the grade.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Sfx = require(UI:WaitForChild("Sfx"))
local StationCard = require(UI:WaitForChild("StationCard"))
local Theme = require(UI:WaitForChild("Theme"))
local TypingInput = require(UI:WaitForChild("TypingInput"))

local PANEL_EXIT_DELAY = 0.35 -- let the last pip pop before the panel drops away
local LOW_TIME_SECONDS = 3
local PANEL_REST = UDim2.new(0.5, 0, 1, -40)
local PANEL_HIDDEN = UDim2.new(0.5, 0, 1, 120)

local STREAK_CALLOUTS: { [number]: string } = { [2] = "DOUBLE CLEAN!", [3] = "PERFECT RUN!" }

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
local field: TypingInput.TypingField? = nil
local currentIndex = 0
local timerTween: Tween? = nil
local fx: Frame
local pips: { Frame } = {}
local cleanStreak = 0

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
		StationCard.Close()
		local newField = TypingInput.Create(panel, TypingInput.DetectMode())
		newField.OnSubmit = function(typed: string)
			RemoteManager.FireServer(RemoteNames.SubmitBurstPrompt, currentIndex, typed)
		end
		field = newField

		maxSeconds = 1
		countdown = RunService.RenderStepped:Connect(function()
			local remaining = math.max(deadline - os.clock(), 0)
			secondsLabel.Text = string.format("%.1fs", remaining)
			local low = remaining > 0 and remaining < LOW_TIME_SECONDS
			timerFill.BackgroundColor3 = if low then Theme.BUG else Theme.ACCENT
			secondsLabel.TextColor3 = if low then Theme.BUG else Theme.ACCENT
			secondsLabel.TextSize = if low then 14 + 4 * math.abs(math.sin(os.clock() * 10)) else 14
		end)

		-- Entrance: the panel springs up from below the screen.
		cleanStreak = 0
		for _, pip in pips do
			pip.BackgroundColor3 = Theme.PANEL
		end
		panel.Position = PANEL_HIDDEN
		gui.Enabled = true
		TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = PANEL_REST,
		}):Play()
	end

	startTimer(if type(timeLeft) == "number" then math.max(timeLeft, 0) else 0)
	if type(timeDelta) == "number" and math.abs(timeDelta) > 0.01 then
		local gained = timeDelta > 0
		local pip = pips[index - 1]
		if pip then
			pip.BackgroundColor3 = if gained then Theme.TYPED else Theme.BUG
			Juice.Pop(pip, 0.8)
		end
		cleanStreak = if gained then cleanStreak + 1 else 0
		local callout = STREAK_CALLOUTS[cleanStreak]
		if callout then
			Sfx.Play("ComboCallout")
			Juice.Banner(fx, callout, Theme.TYPED, 40)
		end
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

local function onFinished(grade: any, accuracy: any, component: any, completed: any, total: any)
	closeField()
	if timerTween then
		timerTween:Cancel()
	end
	local gradeText = if type(grade) == "string" then grade else "C"

	-- The last prompt's pip reflects the overall result (no time change is sent after the final prompt).
	local lastPip = pips[#pips]
	if lastPip then
		lastPip.BackgroundColor3 = if gradeText == "S" or gradeText == "A" then Theme.TYPED else Theme.MOOD
		Juice.Pop(lastPip, 0.8)
	end

	local exit = TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = PANEL_HIDDEN,
	})
	exit.Completed:Once(function()
		if not field then
			gui.Enabled = false
			panel.Position = PANEL_REST
		end
	end)
	task.delay(PANEL_EXIT_DELAY, function()
		if not field then
			exit:Play()
		end
	end)

	StationCard.Show({
		StationName = if type(component) == "string" then GameConfig.STATION_NAMES[component] or "Station" else "Station",
		Grade = gradeText,
		Accuracy = if type(accuracy) == "number" then math.clamp(accuracy, 0, 1) else 0,
		Completed = if type(completed) == "number" then completed else 0,
		Total = if type(total) == "number" then total else GameConfig.BURST_PROMPT_COUNT,
	})
end

function BurstController.Init()
	gui = Theme.Screen("Burst", 4)
	gui.Enabled = false

	fx = Instance.new("Frame")
	fx.BackgroundTransparency = 1
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 10
	fx.Parent = gui

	panel = Theme.Panel(gui, UDim2.fromOffset(640, 0), PANEL_REST)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(panel, 8)

	header = Theme.Text(panel, "", 14, Theme.MUTED)
	header.LayoutOrder = -3

	-- One pip per prompt: green for clean, red for sloppy.
	local pipRow = Instance.new("Frame")
	pipRow.BackgroundTransparency = 1
	pipRow.AnchorPoint = Vector2.new(0.5, 0)
	pipRow.Position = UDim2.fromScale(0.5, 0)
	pipRow.Size = UDim2.fromOffset(120, 16)
	pipRow.Parent = header
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipLayout.Padding = UDim.new(0, 8)
	pipLayout.Parent = pipRow
	for index = 1, GameConfig.BURST_PROMPT_COUNT do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(14, 14)
		pip.BackgroundColor3 = Theme.PANEL
		pip.LayoutOrder = index
		pip.Parent = pipRow
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = pip
		local ring = Instance.new("UIStroke")
		ring.Color = Theme.BORDER
		ring.Parent = pip
		table.insert(pips, pip)
	end

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


	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function BurstController.Start()
	RemoteManager.GetRemote(RemoteNames.BurstPrompt).OnClientEvent:Connect(onPrompt)
	RemoteManager.GetRemote(RemoteNames.BurstFinished).OnClientEvent:Connect(onFinished)
end

return BurstController
