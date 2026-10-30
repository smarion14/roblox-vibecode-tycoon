--!strict
-- Post-deploy results card. Each stat counts up in turn, the performance grade slams in,
-- and the cash payout counts up while "$" coins fly toward the HUD.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Juice = require(script.Parent:WaitForChild("Juice"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Results = {
	Shipped: boolean,
	Payout: number,
	Successes: number,
	Mistakes: number,
	MaxCombo: number,
	Grade: string,
}

local TICK_GAP = 0.045 -- seconds between count tick sounds so fast counts don't machine-gun
local HUD_CASH = UDim2.fromOffset(90, 30)
local GRADE_COLORS: { [string]: Color3 } = {
	S = Theme.MOOD,
	A = Theme.TYPED,
	B = Theme.ACCENT,
	C = Theme.MUTED,
}
local GRADE_STINGERS: { [string]: string } = { S = "GradeS", A = "GradeA", B = "GradeB", C = "GradeC" }

local ResultsScreen = {}

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

local function slamIn(target: GuiObject, from: number)
	local scale = Instance.new("UIScale")
	scale.Scale = from
	scale.Parent = target
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function pause(seconds: number)
	if not skipping then
		task.wait(seconds)
	end
end

local function row(card: Frame, order: number, title: string, color: Color3): TextLabel
	local line = Instance.new("Frame")
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, 34)
	line.LayoutOrder = order
	line.Parent = card
	local name = Theme.Text(line, title, 18, Theme.MUTED)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Size = UDim2.fromScale(0.6, 1)
	local value = Theme.Text(line, "0", 26, color)
	value.Font = Enum.Font.GothamBlack
	value.AutomaticSize = Enum.AutomaticSize.None
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromScale(0.4, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	slamIn(line, 0.6)
	return value
end

local function close()
	local current = gui
	gui = nil
	if current then
		current:Destroy()
	end
end

-- Builds and animates the card. Returns immediately; the animation runs on its own thread.
function ResultsScreen.Show(results: Results)
	close()
	skipping = false

	local screen = Theme.Screen("Results", 7)
	screen.IgnoreGuiInset = true
	gui = screen

	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.BACKGROUND
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = screen
	TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 0.35 }):Play()
	-- Clicking anywhere while it counts skips to the end.
	backdrop.Activated:Connect(function()
		skipping = true
	end)

	local card = Theme.Panel(screen, UDim2.fromOffset(460, 0), UDim2.fromScale(0.5, 0.5))
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.ZIndex = 2
	Theme.List(card, 10)
	slamIn(card, 0.5)

	local title = Theme.Text(card, if results.Shipped then "SHIPPED!" else "LAUNCH FAILED", 40, if results.Shipped
		then Theme.TYPED
		else Theme.BUG)
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 0
	slamIn(title, 2)

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	task.spawn(function()
		pause(0.45)

		-- Successes
		local squashed = row(card, 1, "Bugs squashed", Theme.TYPED)
		Juice.CountUp(squashed, results.Successes, 0.9, tostring, function()
			tick("KeyClick")
		end, function()
			return skipping
		end)
		Juice.Pop(squashed, 0.3)
		pause(0.25)

		-- Mistakes
		local mistakes = row(card, 2, "Mistakes", Theme.BUG)
		Juice.CountUp(mistakes, results.Mistakes, 0.7, tostring, function()
			tick("KeyWrong")
		end, function()
			return skipping
		end)
		if results.Mistakes == 0 then
			mistakes.Text = "0  PERFECT!"
			mistakes.TextColor3 = Theme.MOOD
			Sfx.Play("ComboCallout")
		end
		Juice.Pop(mistakes, 0.3)
		pause(0.25)

		-- Best streak
		local combo = row(card, 3, "Best combo", Theme.ACCENT)
		Juice.CountUp(combo, results.MaxCombo, 0.6, function(value: number): string
			return `x{value}`
		end, function()
			tick("ChipTap")
		end, function()
			return skipping
		end)
		Juice.Pop(combo, 0.3)
		pause(0.35)

		-- Performance grade: stamped in big and tilted, then settles.
		local gradeLine = row(card, 4, "Performance", GRADE_COLORS[results.Grade] or Theme.MUTED)
		gradeLine.Text = results.Grade
		gradeLine.TextSize = 40
		gradeLine.Rotation = math.random(-15, 15)
		local gradeScale = gradeLine:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		gradeScale.Parent = gradeLine
		gradeScale.Scale = 3
		TweenService:Create(gradeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(gradeLine, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		Sfx.Play("GradeStamp")
		task.delay(0.12, function()
			Sfx.Play((GRADE_STINGERS[results.Grade] or "GradeC") :: any)
		end)
		if results.Grade == "S" or results.Grade == "A" then
			for _ = 1, if results.Grade == "S" then 14 else 7 do
				-- On the screen, not in the card: anything parented into the card's list layout becomes a row.
				Juice.Spark(screen :: any, UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.3, 0.55), GRADE_COLORS[results.Grade])
			end
		end
		pause(0.6)

		-- Cash: counts up while coins fly to the HUD.
		local cash = row(card, 5, "Cash earned", Theme.TYPED)
		cash.TextSize = 32
		if results.Shipped and results.Payout > 0 then
			Juice.CountUp(cash, results.Payout, 1.6, function(value: number): string
				return `+${value}`
			end, function()
				tick("ChipTap")
				if not skipping and math.random() < 0.5 then
					Juice.Coin(screen :: any, UDim2.fromScale(0.5, 0.62), HUD_CASH)
				end
			end, function()
				return skipping
			end)
			Sfx.Play("GradeSCash")
			Juice.Pop(cash, 0.5)
			for _ = 1, 10 do
				Juice.Coin(screen :: any, UDim2.fromScale(0.5, 0.62), HUD_CASH)
			end
		else
			cash.Text = "$0"
			local note = Theme.Text(card, "Your components are safe. Try the deploy again!", 14, Theme.MOOD)
			note.TextXAlignment = Enum.TextXAlignment.Center
			note.LayoutOrder = 6
		end
		pause(0.3)

		local continue = Theme.Button(card, "Continue", 18)
		continue.LayoutOrder = 10
		slamIn(continue, 0.4)
		continue.Activated:Connect(close)
	end)
end

return ResultsScreen
