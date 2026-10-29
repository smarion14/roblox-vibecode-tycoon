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

local function homeOf(target: GuiObject): UDim2
	local home = target:GetAttribute("JuiceHome")
	if typeof(home) == "UDim2" then
		return home
	end
	target:SetAttribute("JuiceHome", target.Position)
	return target.Position
end

-- A typed letter lands: it springs up big, then drops back into place with a bounce.
function Juice.Hop(letter: GuiObject)
	local home = homeOf(letter)
	local scale = scaleOf(letter)
	letter.Position = home + UDim2.fromOffset(0, -14)
	letter.Rotation = rng:NextInteger(-12, 12)
	scale.Scale = 1.6
	TweenService:Create(letter, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Position = home,
		Rotation = 0,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Every letter hops in sequence, left to right, like a wave running through the line.
function Juice.Wave(letters: { GuiObject })
	for index, letter in letters do
		task.delay(index * 0.012, Juice.Hop, letter)
	end
end

-- Smoothly moves the typing cursor to the next letter.
function Juice.Slide(target: GuiObject, position: UDim2)
	TweenService:Create(target, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = position }):Play()
end

-- Quick scale tick, for touch chips on a correct tap.
function Juice.Pop(target: GuiObject, amount: number)
	local scale = scaleOf(target)
	scale.Scale = 1 + amount
	TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Appears from nothing with an overshoot, for things spawning in.
function Juice.PopIn(target: GuiObject)
	local scale = scaleOf(target)
	scale.Scale = 0
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Squash payoff: an expanding ring, a big "SPLAT" glyph and a spray of sparks at the bug's last position.
function Juice.Splat(layer: GuiObject, position: UDim2)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = position
	ring.Size = UDim2.fromOffset(20, 20)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 9
	ring.Parent = layer
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.TYPED
	stroke.Thickness = 3
	stroke.Parent = ring
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(110, 110),
	}):Play()
	local fade = TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 })
	fade.Completed:Once(function()
		ring:Destroy()
	end)
	fade:Play()

	local splat = Instance.new("TextLabel")
	splat.BackgroundTransparency = 1
	splat.AnchorPoint = Vector2.new(0.5, 0.5)
	splat.Position = position
	splat.Size = UDim2.fromOffset(120, 30)
	splat.Font = Theme.FONT
	splat.TextSize = 22
	splat.TextColor3 = Theme.ACCENT
	splat.TextStrokeTransparency = 0.5
	splat.Text = "SPLAT!"
	splat.Rotation = rng:NextInteger(-15, 15)
	splat.ZIndex = 10
	splat.Parent = layer
	local splatScale = scaleOf(splat)
	splatScale.Scale = 0.3
	TweenService:Create(splatScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.2 }):Play()
	local rise = TweenService:Create(splat, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = position + UDim2.fromOffset(0, -40),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	rise.Completed:Once(function()
		splat:Destroy()
	end)
	rise:Play()

	for _ = 1, 8 do
		Juice.Spark(layer, position, if rng:NextNumber() < 0.5 then Theme.TYPED else Theme.ACCENT)
	end
end

-- Horizontal shake plus an optional red flash behind the target. The target must not be positioned by a UILayout.
function Juice.Shake(target: GuiObject, flash: GuiObject?)
	local origin = homeOf(target)

	task.spawn(function()
		for step, offset in SHAKE_OFFSETS do
			target.Position = origin + UDim2.fromOffset(offset, if step % 2 == 0 then 2 else -2)
			target.Rotation = offset * 1.5
			task.wait(SHAKE_STEP_SECONDS)
		end
		target.Position = origin
		target.Rotation = 0
	end)

	if flash then
		flash.BackgroundColor3 = Theme.BUG
		flash.BackgroundTransparency = 0.6
		TweenService:Create(flash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end
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
