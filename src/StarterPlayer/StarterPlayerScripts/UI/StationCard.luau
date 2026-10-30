--!strict
-- Station burst result card: accuracy and prompts count up, the quality grade stamps in, and the part you built
-- is shown. It stays until the player clicks Continue, or closes on its own after AUTO_CLOSE_SECONDS.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Juice = require(script.Parent:WaitForChild("Juice"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type StationResult = {
	StationName: string,
	Grade: string,
	Accuracy: number, -- 0-1
	Completed: number,
	Total: number,
	ProgressLabel: string?, -- e.g. "Prompts finished", "Rounds cleared"
	ScoreLabel: string?, -- e.g. "Accuracy", "Precision"
}

local AUTO_CLOSE_SECONDS = 8
local TICK_GAP = 0.045

-- Grade styling: colour, banner text (nil = no banner) and how many sparks fly.
local GRADE_STYLE: { [string]: { Color: Color3, Banner: string?, Sparks: number } } = {
	S = { Color = Theme.MOOD, Banner = "S RANK! FLAWLESS", Sparks = 18 },
	A = { Color = Theme.TYPED, Banner = "A RANK!", Sparks = 10 },
	B = { Color = Theme.ACCENT, Banner = nil, Sparks = 4 },
	C = { Color = Theme.MUTED, Banner = nil, Sparks = 0 },
}

local StationCard = {}

local gui: ScreenGui? = nil
local skipping = false
local lastTick = 0

local function tick(sound: Sfx.SoundName)
	local now = os.clock()
	if now - lastTick >= TICK_GAP then
		lastTick = now
		Sfx.Play(sound)
	end
end

local function pause(seconds: number)
	if not skipping then
		task.wait(seconds)
	end
end

local function slamIn(target: GuiObject, from: number)
	local scale = Instance.new("UIScale")
	scale.Scale = from
	scale.Parent = target
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function row(card: Frame, order: number, title: string, color: Color3): TextLabel
	local line = Instance.new("Frame")
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, 32)
	line.LayoutOrder = order
	line.Parent = card
	local name = Theme.Text(line, title, 17, Theme.MUTED)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Size = UDim2.fromScale(0.6, 1)
	local value = Theme.Text(line, "0", 24, color)
	value.Font = Enum.Font.GothamBlack
	value.AutomaticSize = Enum.AutomaticSize.None
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromScale(0.4, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	slamIn(line, 0.6)
	return value
end

function StationCard.Close()
	local current = gui
	gui = nil
	if current then
		Sfx.Play("CardClose")
		current:Destroy()
	end
end

function StationCard.Show(result: StationResult)
	-- Replacing an open card shouldn't play the close whoosh over the new card's entrance.
	local previous = gui
	gui = nil
	if previous then
		previous:Destroy()
	end
	skipping = false
	local style = GRADE_STYLE[result.Grade] or GRADE_STYLE.C

	local screen = Theme.Screen("StationCard", 6)
	gui = screen

	-- Clicking anywhere while it animates jumps to the end. This sits behind the card at screen level:
	-- inside the card's list layout a full-size button would stretch the card to fill the screen.
	local skipCatcher = Instance.new("TextButton")
	skipCatcher.Text = ""
	skipCatcher.AutoButtonColor = false
	skipCatcher.BackgroundTransparency = 1
	skipCatcher.Size = UDim2.fromScale(1, 1)
	skipCatcher.Parent = screen
	skipCatcher.Activated:Connect(function()
		skipping = true
	end)

	local card = Theme.Panel(screen, UDim2.fromOffset(400, 0), UDim2.fromScale(0.5, 0.45))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(card, 8)
	slamIn(card, 0.5)

	local title = Theme.Text(card, string.upper(result.StationName), 26, Theme.ACCENT)
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 0
	slamIn(title, 1.8)

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Sfx.Play("CardOpen")

	task.spawn(function()
		pause(0.3)

		local accuracy = row(card, 1, result.ScoreLabel or "Accuracy", Theme.TYPED)
		Juice.CountUp(accuracy, math.floor(result.Accuracy * 100 + 0.5), 0.8, function(value: number): string
			return `{value}%`
		end, function()
			tick("KeyClick")
		end, function()
			return skipping
		end)
		Juice.Pop(accuracy, 0.3)
		if result.Accuracy >= 0.995 then
			accuracy.TextColor3 = Theme.MOOD
			Sfx.Play("PromptClean") -- a perfect 100% gets its own chime
		end
		pause(0.2)

		local prompts = row(card, 2, result.ProgressLabel or "Prompts finished", Theme.TEXT)
		Juice.CountUp(prompts, result.Completed, 0.5, function(value: number): string
			return `{value} / {result.Total}`
		end, function()
			tick("ChipTap")
		end, function()
			return skipping
		end)
		if result.Completed >= result.Total then
			prompts.TextColor3 = Theme.TYPED
			Sfx.Play("ChipTap")
		else
			Sfx.Play("KeyWrong")
		end
		Juice.Pop(prompts, 0.3)
		pause(0.3)

		-- Quality grade: stamped in big and tilted, then settles.
		local gradeLine = row(card, 3, "Quality", style.Color)
		gradeLine.Text = result.Grade
		gradeLine.TextSize = 40
		gradeLine.Rotation = math.random(-15, 15)
		local gradeScale = gradeLine:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		gradeScale.Parent = gradeLine
		gradeScale.Scale = 3
		TweenService:Create(gradeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(gradeLine, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		Sfx.Play("GradeStamp")
		task.delay(0.12, function()
			if result.Grade == "S" then
				Sfx.Play("GradeS")
				Sfx.Play("GradeSCash")
				Sfx.Play("ComboCallout")
			elseif result.Grade == "A" then
				Sfx.Play("GradeA")
			elseif result.Grade == "B" then
				Sfx.Play("GradeB")
			else
				Sfx.Play("GradeC")
			end
		end)
		if style.Banner then
			Juice.Banner(screen :: any, style.Banner, style.Color, 46)
		end
		for _ = 1, style.Sparks do
			Juice.Spark(screen :: any, UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.3, 0.5), style.Color)
		end
		pause(0.5)

		-- The part that goes into your inventory.
		local earned = Theme.Text(card, `+1 {result.StationName}  ({result.Grade})`, 18, style.Color)
		earned.TextXAlignment = Enum.TextXAlignment.Center
		earned.LayoutOrder = 4
		slamIn(earned, 0.4)
		Sfx.Play("PartEarned")
		pause(0.2)

		local continue = Theme.Button(card, "Continue", 16)
		continue.LayoutOrder = 10
		slamIn(continue, 0.4)
		continue.Activated:Connect(StationCard.Close)

		-- A draining bar shows when the card will close by itself.
		local timerBack = Instance.new("Frame")
		timerBack.Size = UDim2.new(1, 0, 0, 4)
		timerBack.BackgroundColor3 = Theme.PANEL
		timerBack.BorderSizePixel = 0
		timerBack.LayoutOrder = 11
		timerBack.Parent = card
		local timerFill = Instance.new("Frame")
		timerFill.Size = UDim2.fromScale(1, 1)
		timerFill.BackgroundColor3 = Theme.MUTED
		timerFill.BorderSizePixel = 0
		timerFill.Parent = timerBack
		TweenService:Create(timerFill, TweenInfo.new(AUTO_CLOSE_SECONDS, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
		task.delay(AUTO_CLOSE_SECONDS, function()
			if gui == screen then
				StationCard.Close()
			end
		end)
	end)
end

return StationCard
