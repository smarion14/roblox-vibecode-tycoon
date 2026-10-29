--!strict
-- Typing feedback effects for ScreenGui. ParticleEmitters don't render in 2D UI, so these are tweened GuiObjects.
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local SPARK_GLYPHS = { "✦", "✧", "+", "•" }
local SPARK_SECONDS = 0.35
local SHAKE_OFFSETS = { 8, -7, 5, -3, 0 }
local SHAKE_STEP_SECONDS = 0.035

local Juice = {}

local rng = Random.new()

local function scaleOf(target: GuiObject): UIScale
	local existing = target:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Parent = target
	return scale
end

-- Tiny glyph that bursts out of a point and fades. Called on every correct keystroke.
function Juice.Spark(layer: GuiObject, position: UDim2, color: Color3)
	local spark = Instance.new("TextLabel")
	spark.BackgroundTransparency = 1
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.Position = position
	spark.Size = UDim2.fromOffset(18, 18)
	spark.Font = Theme.FONT
	spark.TextSize = rng:NextInteger(12, 18)
	spark.TextColor3 = color
	spark.Text = SPARK_GLYPHS[rng:NextInteger(1, #SPARK_GLYPHS)]
	spark.Rotation = rng:NextInteger(-30, 30)
	spark.ZIndex = 10
	spark.Parent = layer

	local drift = UDim2.fromOffset(rng:NextInteger(-18, 18), rng:NextInteger(-34, -16))
	local tween = TweenService:Create(spark, TweenInfo.new(SPARK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = position + drift,
		TextTransparency = 1,
		Rotation = spark.Rotation + rng:NextInteger(-90, 90),
	})
	tween.Completed:Once(function()
		spark:Destroy()
	end)
	tween:Play()
end

-- Quick scale tick, for the prompt line on each correct key.
function Juice.Pop(target: GuiObject, amount: number)
	local scale = scaleOf(target)
	scale.Scale = 1 + amount
	TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Horizontal shake plus a red flash behind the target. The target must not be positioned by a UILayout.
function Juice.Shake(target: GuiObject, flash: GuiObject)
	local home = target:GetAttribute("JuiceHome")
	if typeof(home) ~= "UDim2" then
		home = target.Position
		target:SetAttribute("JuiceHome", home)
	end
	local origin = home :: UDim2

	task.spawn(function()
		for _, offset in SHAKE_OFFSETS do
			target.Position = origin + UDim2.fromOffset(offset, 0)
			task.wait(SHAKE_STEP_SECONDS)
		end
		target.Position = origin
	end)

	flash.BackgroundColor3 = Theme.BUG
	flash.BackgroundTransparency = 0.6
	TweenService:Create(flash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
end

-- Prompt done: the line jumps and bounces back, and a label leaps up out of it.
function Juice.Bounce(target: GuiObject, layer: GuiObject, text: string)
	local scale = scaleOf(target)
	scale.Scale = 1
	local up = TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.12 })
	up.Completed:Once(function()
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	up:Play()

	local badge = Instance.new("TextLabel")
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.Size = UDim2.fromOffset(220, 40)
	badge.Font = Theme.FONT
	badge.TextSize = 30
	badge.TextColor3 = Theme.TYPED
	badge.TextStrokeTransparency = 0.4
	badge.Text = text
	badge.ZIndex = 11
	badge.Parent = layer

	local badgeScale = scaleOf(badge)
	badgeScale.Scale = 0.4
	TweenService:Create(badgeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local rise = TweenService:Create(badge, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.5, -60),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	rise.Completed:Once(function()
		badge:Destroy()
	end)
	rise:Play()

	for _ = 1, 10 do
		Juice.Spark(layer, UDim2.new(rng:NextNumber(0.2, 0.8), 0, 0.5, 0), if rng:NextNumber() < 0.5 then Theme.TYPED else Theme.ACCENT)
	end
end

return Juice
