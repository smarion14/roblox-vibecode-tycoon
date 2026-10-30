--!strict
-- Deploy battle screen. Bugs only: two waves, then a boss bug whose phrase is typed word by word.
-- Left: the client on a live call. Centre: wave, ship progress, combo, the bug lane and YOUR CODE line.
-- Server BattleUpdate snapshots are the truth; bug motion is animated locally from the server start time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Music = require(UI:WaitForChild("Music"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))
local TypingInput = require(UI:WaitForChild("TypingInput"))

type BugView = {
	Id: number,
	Kind: string,
	Wave: number,
	Word: string,
	Words: { string },
	Hp: number,
	Side: number,
	SpawnOffset: number,
	ReachOffset: number,
	LastHitOffset: number,
	State: string,
	Button: TextButton,
	Stroke: UIStroke,
	Hint: TextLabel,
	Shown: boolean,
}

local RESULT_SECONDS = 3
local BUG_LANES = 5
local DANGER_TRAVEL = 0.75 -- past this share of the path a bug starts pulsing as a warning
local PRAISE_CHANCE = 0.45
local INSTRUCTION_KEYBOARD = "Bugs crawl toward YOUR CODE. Type a bug's name + SPACE to squash it."
local INSTRUCTION_TOUCH = "Bugs crawl toward YOUR CODE. Tap a bug to squash it."

local PRAISE = { "clean!", "squashed!", "nice!", "gone!", "patched!", "fixed!" }
local COMBO_CALLOUTS: { [number]: string } = {
	[3] = "NICE!",
	[5] = "AMAZING!",
	[8] = "ON FIRE!",
	[10] = "SHIP! SHIP! SHIP!",
	[15] = "UNSTOPPABLE!",
	[20] = "10x ENGINEER!",
	[25] = "LEGENDARY DEV!",
}

-- What the client says on the call when something good happens.
local CLIENT_LINES: { [string]: { string } } = {
	Squash = {
		"Wow, this app is great!",
		"Ooh, smooth!",
		"That bug's gone? Nice.",
		"Clean work!",
		"I like where this is going.",
		"My customers will love this!",
		"Fast AND pretty?",
		"Okay, I'm impressed.",
	},
	BossHit = { "You're breaking it apart!", "Keep going, keep going!", "Get that thing!", "It's cracking!" },
	BossDown = { "YOU DID IT! That was the big one!", "Is it fixed?! It's FIXED!", "Best developer ever!" },
	Combo = { "You're on a roll!", "Are you even human?", "This is going viral!", "Teach me your ways!" },
}
local HAPPY_FACES = { "😍", "🤩", "😆", "🥳" }
local MAX_BUBBLES = 3
local BUBBLE_SECONDS = 3.5
local SQUASH_LINE_COOLDOWN = 0.7 -- squashes can land every half second; don't bury the sidebar in bubbles

local REACTIONS = {
	happy = { "Oh nice, that loads fast.", "This is exactly what I pictured.", "My team is going to love this." },
	neutral = { "Okay, keep going.", "Hmm, interesting choice.", "Is that how it's supposed to look?" },
	annoyed = { "Wait, is it supposed to flash like that?", "It froze again.", "I'm not paying for broken." },
}

local BattleController = {}

local gui: ScreenGui
local root: Frame
local rootFlash: Frame
local clientName: TextLabel
local face: TextLabel
local bubbleStack: Frame
local faceBand = ""
local faceToken = 0
local lastSquashLine = 0
local bubbleOrder = 0
local moodFill: Frame
local comboLabel: TextLabel
local waveLabel: TextLabel
local progressFill: Frame
local instructionLabel: TextLabel
local inputHolder: Frame
local bugLayer: Frame
local resultLabel: TextLabel

local catcher: TypingInput.WordCatcher? = nil
local mode: TypingInput.Mode = "Keyboard"
local bugs: { BugView } = {}
local serverStart = 0
local waveCount = 2
local announcedWave = 0
local lastMoodBand = ""
local lastCombo = 0
local partialWord = ""
local squashedOnce = false
local renderConnection: RBXScriptConnection? = nil

local function serverElapsed(): number
	return Workspace:GetServerTimeNow() - serverStart
end

local function moodBand(mood: number): string
	if mood > 70 then
		return "happy"
	elseif mood >= 40 then
		return "neutral"
	end
	return "annoyed"
end

-- Chat bubble from the client: pops in from the face with an overshoot, settles, then fades out.
-- Good news gets a green edge, complaints a red one. Only the newest few stay on screen.
local function clientSay(text: string, positive: boolean)
	bubbleOrder += 1
	local bubble = Instance.new("Frame")
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.Size = UDim2.new(1, 0, 0, 0)
	bubble.BackgroundColor3 = Theme.PANEL
	bubble.LayoutOrder = -bubbleOrder -- newest on top
	bubble.Parent = bubbleStack
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = if positive then Theme.TYPED else Theme.BUG
	stroke.Thickness = 2
	stroke.Parent = bubble
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = bubble
	local label = Theme.Text(bubble, `"{text}"`, 15, if positive then Theme.TEXT else Theme.BUG)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = bubble
	bubble.Rotation = math.random(-6, 6)
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bubble, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()

	local bubbles: { Frame } = {}
	for _, child in bubbleStack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(bubbles, child)
		end
	end
	table.sort(bubbles, function(a: Frame, b: Frame): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = MAX_BUBBLES + 1, #bubbles do
		bubbles[index]:Destroy()
	end

	task.delay(BUBBLE_SECONDS, function()
		if bubble.Parent then
			TweenService:Create(bubble, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			local fade = TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 })
			fade.Completed:Once(function()
				bubble:Destroy()
			end)
			fade:Play()
		end
	end)
end

local function bandFace(): string
	return if faceBand == "happy" then "😄" elseif faceBand == "neutral" then "😐" else "😬"
end

-- The client lights up for a moment: delighted face, a wiggle and a bounce, plus a green pulse on the mood bar.
local function clientCheer(text: string)
	faceToken += 1
	local token = faceToken
	face.Text = HAPPY_FACES[math.random(1, #HAPPY_FACES)]
	Juice.Pop(face, 0.55)
	face.Rotation = math.random(-15, 15)
	TweenService:Create(face, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	moodFill.BackgroundColor3 = Theme.TYPED
	TweenService:Create(moodFill, TweenInfo.new(0.5), { BackgroundColor3 = Theme.MOOD }):Play()
	clientSay(text, true)
	task.delay(0.9, function()
		if faceToken == token then
			face.Text = bandFace()
		end
	end)
end

local function cheerFrom(kind: string)
	local lines = CLIENT_LINES[kind]
	clientCheer(lines[math.random(1, #lines)])
end

local function setMood(mood: number)
	moodFill.Size = UDim2.fromScale(math.clamp(mood / 100, 0, 1), 1)
	local band = moodBand(mood)
	faceBand = band
	if band ~= lastMoodBand then
		local dropped = lastMoodBand ~= ""
		lastMoodBand = band
		face.Text = bandFace()
		Juice.Pop(face, 0.4)
		-- A drop in mood is worth saying out loud; the opening line is set in onStarted.
		if dropped and band ~= "happy" then
			local lines = REACTIONS[band]
			clientSay(lines[math.random(1, #lines)], false)
		end
	end
end

local function clearBattle()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if catcher then
		catcher:Destroy()
		catcher = nil
	end
	for _, bug in bugs do
		bug.Button:Destroy()
	end
	table.clear(bugs)
end

local function bossNextWord(bug: BugView): string?
	return bug.Words[#bug.Words - bug.Hp + 1]
end

-- The boss shows its phrase with broken words green, the next word white and the rest red.
local function bossText(bug: BugView): string
	local parts: { string } = {}
	local done = #bug.Words - bug.Hp
	for index, word in bug.Words do
		if index <= done then
			table.insert(parts, `<font color="#{Theme.TYPED:ToHex()}"><s>{word}</s></font>`)
		elseif index == done + 1 then
			table.insert(parts, `<u><font color="#ffffff">{word}</font></u>`)
		else
			table.insert(parts, word)
		end
	end
	return `👾 {table.concat(parts, " ")}  {string.rep("♥", bug.Hp)}`
end

-- Mirrors the server's rule: a word can't be typed faster than its target appeared (or was last hit).
local function canHit(bug: BugView, word: string, elapsed: number): boolean
	local earliest = bug.LastHitOffset + #word / GameConfig.BATTLE_RULES.MaxCharsPerSecond
	return bug.State == "Pending" and elapsed >= earliest
end

-- Only sends a squash when it matches a visible target, so typos don't cost the player anything.
local function trySquashWord(word: string): boolean
	local elapsed = serverElapsed()
	for _, bug in bugs do
		if bug.Kind == "Boss" and bossNextWord(bug) == word and canHit(bug, word, elapsed) then
			RemoteManager.FireServer(RemoteNames.BattleSquash, word)
			return true
		end
	end
	for _, bug in bugs do
		if bug.Kind == "Minion" and bug.Word == word and canHit(bug, word, elapsed) then
			RemoteManager.FireServer(RemoteNames.BattleSquash, word)
			return true
		end
	end
	return false
end

local function announceWave(elapsed: number)
	for _, bug in bugs do
		if bug.Wave > announcedWave and elapsed >= bug.SpawnOffset - 0.8 then
			announcedWave = bug.Wave
			if bug.Wave > waveCount then
				waveLabel.Text = "BOSS WAVE"
				Sfx.Play("Banner")
				Music.Play("Boss", 1.5)
				Juice.Banner(root, "⚠ BOSS BUG INCOMING ⚠", Theme.BUG)
			else
				waveLabel.Text = `WAVE {bug.Wave} / {waveCount}`
				Sfx.Play("Banner")
				Juice.Banner(root, `WAVE {bug.Wave}`, Theme.MOOD)
			end
			Juice.Pop(waveLabel, 0.4)
			return
		end
	end
end

local function renderBugs()
	local elapsed = serverElapsed()
	announceWave(elapsed)

	for _, bug in bugs do
		local visible = bug.State == "Pending" and elapsed >= bug.SpawnOffset
		bug.Button.Visible = visible
		if not visible then
			continue
		end
		if not bug.Shown then
			bug.Shown = true
			Juice.PopIn(bug.Button)
		end

		local travel = math.clamp((elapsed - bug.SpawnOffset) / (bug.ReachOffset - bug.SpawnOffset), 0, 1)
		local x = if bug.Side < 0 then 0.5 * travel else 1 - 0.5 * travel
		local laneY = if bug.Kind == "Boss" then 0.5 else 0.1 + ((bug.Id % BUG_LANES) / BUG_LANES) * 0.8
		local phase = elapsed * (if bug.Kind == "Boss" then 4 else 10) + bug.Id
		-- Crawl: a side-to-side wiggle and a small bob so the bug looks alive.
		bug.Button.Rotation = math.sin(phase) * (if bug.Kind == "Boss" then 3 else 8)
		bug.Button.Position = UDim2.new(x, 0, laneY, math.sin(phase * 1.7) * 3)

		-- Warning phase: close to your code the bug flashes and throbs.
		local danger = travel >= DANGER_TRAVEL
		local scale = bug.Button:FindFirstChildOfClass("UIScale")
		if scale and scale.Scale >= 0.99 then
			scale.Scale = if danger then 1 + 0.12 * math.abs(math.sin(elapsed * 14)) else 1
		end
		bug.Button.BackgroundColor3 = if danger and math.sin(elapsed * 14) > 0
			then Color3.fromRGB(120, 20, 40)
			else Color3.fromRGB(42, 15, 28)

		-- Targeting: the bug whose name you're typing lights up, so you know the squash is aimed right.
		local target = if bug.Kind == "Boss" then bossNextWord(bug) or "" else bug.Word
		local targeted = partialWord ~= "" and string.sub(target, 1, #partialWord) == partialWord
		bug.Stroke.Color = if targeted then Theme.TYPED else Theme.BUG
		bug.Stroke.Thickness = if targeted then 3 else (if bug.Kind == "Boss" then 2 else 1)

		-- Until the first squash, each bug carries its own instruction.
		bug.Hint.Visible = not squashedOnce or bug.Kind == "Boss"
	end
end

local function makeBug(info: any): BugView
	local isBoss = info.Kind == "Boss"
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = if isBoss then UDim2.fromOffset(320, 52) else UDim2.fromOffset(96, 30)
	button.BackgroundColor3 = Color3.fromRGB(42, 15, 28)
	button.TextColor3 = Theme.BUG
	button.Font = Theme.FONT
	button.TextSize = if isBoss then 18 else 16
	button.RichText = isBoss
	button.Text = `🐛 {info.Word}`
	button.Visible = false
	button.AutoButtonColor = mode == "Touch"
	button.ZIndex = if isBoss then 3 else 2
	button.Parent = bugLayer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.BUG
	stroke.Thickness = if isBoss then 2 else 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 0, -4)
	hint.Size = UDim2.fromOffset(240, 18)
	hint.Font = Theme.FONT
	hint.TextSize = 14
	hint.TextColor3 = Theme.MOOD
	hint.TextStrokeTransparency = 0.3
	hint.Text = if isBoss
		then (if mode == "Touch" then "tap it once per word!" else "type each word in order + SPACE!")
		else (if mode == "Touch" then "tap me!" else `type "{info.Word}" + SPACE`)
	hint.Parent = button

	local words: { string } = {}
	if type(info.Words) == "table" then
		for _, word in info.Words do
			table.insert(words, tostring(word))
		end
	end

	local view: BugView = {
		Id = info.Id,
		Kind = if isBoss then "Boss" else "Minion",
		Wave = tonumber(info.Wave) or 1,
		Word = tostring(info.Word),
		Words = words,
		Hp = #words,
		Side = info.Side,
		SpawnOffset = info.SpawnOffset,
		ReachOffset = info.ReachOffset,
		LastHitOffset = info.SpawnOffset,
		State = "Pending",
		Button = button,
		Stroke = stroke,
		Hint = hint,
		Shown = false,
	}
	if isBoss then
		button.Text = bossText(view)
	end

	button.Activated:Connect(function()
		if mode ~= "Touch" then
			return
		end
		local word = if view.Kind == "Boss" then bossNextWord(view) else view.Word
		if word and canHit(view, word, serverElapsed()) then
			RemoteManager.FireServer(RemoteNames.BattleSquash, word)
		end
	end)
	return view
end

local function onStarted(info: any)
	if type(info) ~= "table" or type(info.Bugs) ~= "table" then
		return
	end
	clearBattle()
	serverStart = tonumber(info.ServerStart) or Workspace:GetServerTimeNow()
	waveCount = tonumber(info.WaveCount) or 2
	announcedWave = 0
	clientName.Text = tostring(info.ClientName)
	lastMoodBand = ""
	faceToken += 1
	lastSquashLine = 0
	for _, child in bubbleStack:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	setMood(tonumber(info.Mood) or 70)
	clientSay("Okay, show me what you've got!", true)
	comboLabel.Text = "x0"
	lastCombo = 0
	partialWord = ""
	squashedOnce = false
	waveLabel.Text = "GET READY"
	progressFill.Size = UDim2.fromScale(0, 1)
	resultLabel.Visible = false
	mode = TypingInput.DetectMode()
	instructionLabel.Text = if mode == "Touch" then INSTRUCTION_TOUCH else INSTRUCTION_KEYBOARD

	for _, bug in info.Bugs do
		table.insert(bugs, makeBug(bug))
	end

	if mode == "Keyboard" then
		local newCatcher = TypingInput.CreateWordCatcher(inputHolder)
		newCatcher.OnWord = trySquashWord
		newCatcher.OnPartial = function(partial: string)
			partialWord = partial
		end
		catcher = newCatcher
	end

	renderConnection = RunService.RenderStepped:Connect(renderBugs)
	Music.Play("Battle", 0.8)
	gui.Enabled = true
end

local function celebrateCombo(combo: number)
	-- The multiplier grows and heats up the longer the streak runs.
	Juice.Pop(comboLabel, 0.25 + math.min(combo, 20) * 0.02)
	comboLabel.TextColor3 = if combo >= 10 then Theme.TYPED elseif combo >= 5 then Theme.MOOD else Theme.ACCENT
	local callout = COMBO_CALLOUTS[combo]
	if callout then
		if combo >= 5 then
			cheerFrom("Combo")
		end
		Sfx.Play("ComboCallout")
		Juice.Banner(root, callout, if combo >= 10 then Theme.TYPED else Theme.ACCENT, if combo >= 10 then 54 else 46)
		for _ = 1, 6 do
			Juice.Spark(comboLabel, UDim2.fromScale(math.random(), 0.5), Theme.ACCENT)
		end
	end
end

local function onBugSquashed(bug: BugView)
	squashedOnce = true
	local now = os.clock()
	if now - lastSquashLine >= SQUASH_LINE_COOLDOWN then
		lastSquashLine = now
		cheerFrom("Squash")
	end
	Sfx.Play("Splat")
	Juice.Splat(bugLayer, bug.Button.Position)
	if math.random() < PRAISE_CHANCE then
		Juice.FloatText(bugLayer, bug.Button.Position + UDim2.fromOffset(0, -30), PRAISE[math.random(1, #PRAISE)], Theme.TYPED)
	end
end

local function onBossHit(bug: BugView, newHp: number)
	cheerFrom("BossHit")
	bug.Hp = newHp
	bug.LastHitOffset = serverElapsed()
	bug.Button.Text = bossText(bug)
	Sfx.Play("BossHit")
	Sfx.Play("Splat")
	Juice.Shake(bug.Button, nil)
	Juice.FloatText(bugLayer, bug.Button.Position + UDim2.fromOffset(0, -40), "CRACK!", Theme.MOOD)
	for _ = 1, 5 do
		Juice.Spark(bugLayer, bug.Button.Position, Theme.MOOD)
	end
end

local function onUpdate(snapshot: any)
	if type(snapshot) ~= "table" or not renderConnection then
		return
	end
	setMood(tonumber(snapshot.Mood) or 0)
	progressFill.Size = UDim2.fromScale(math.clamp(tonumber(snapshot.Progress) or 0, 0, 1), 1)

	local combo = tonumber(snapshot.Combo) or 0
	comboLabel.Text = `x{combo}`
	if combo > lastCombo then
		celebrateCombo(combo)
	elseif combo == 0 and lastCombo > 0 then
		comboLabel.TextColor3 = Theme.ACCENT
		Juice.Shake(comboLabel, nil)
	end
	lastCombo = combo

	local bossHp = tonumber(snapshot.BossHp)
	for _, bug in bugs do
		if bug.Kind == "Boss" and bossHp and bossHp < bug.Hp and bossHp > 0 then
			onBossHit(bug, bossHp)
		end
	end

	if type(snapshot.BugStates) ~= "table" then
		return
	end
	for _, bug in bugs do
		local state = snapshot.BugStates[bug.Id]
		if type(state) ~= "string" or bug.State ~= "Pending" or state == "Pending" then
			continue
		end
		if state == "Squashed" then
			if bug.Kind == "Boss" then
				-- Peak moment: the boss breaks.
				bug.Hp = 0
				Juice.Splat(bugLayer, bug.Button.Position)
				Juice.Splat(bugLayer, bug.Button.Position + UDim2.fromOffset(60, 0))
				Juice.Splat(bugLayer, bug.Button.Position + UDim2.fromOffset(-60, 0))
				Juice.Banner(root, "BOSS DOWN!", Theme.TYPED, 58)
				cheerFrom("BossDown")
				rootFlash.BackgroundColor3 = Theme.TYPED
				rootFlash.BackgroundTransparency = 0.6
				Sfx.Play("BossDown")
				Sfx.Play("BossHit")
				task.delay(0.15, function()
					rootFlash.BackgroundTransparency = 1
				end)
			else
				onBugSquashed(bug)
			end
		elseif state == "Hit" then
			-- Contact: a bug got through. Shake the whole screen and flash it red.
			Sfx.Play("BugGotThrough")
			Juice.Shake(root, rootFlash)
			Juice.FloatText(moodFill, UDim2.fromScale(0.5, -1.5), "OUCH", Theme.BUG)
		end
		bug.State = state
	end
end

local function onEnded(result: any, payout: any)
	clearBattle()
	Music.Stop(2)
	local shipped = type(result) == "table" and result.Status == "Shipped"
	if shipped then
		Sfx.Play("Shipped")
		Juice.Banner(root, "SHIPPED!", Theme.TYPED, 64)
		for _ = 1, 16 do
			Juice.Spark(root, UDim2.fromScale(math.random(), math.random() * 0.6 + 0.2), Theme.TYPED)
		end
	end
	resultLabel.Text = if shipped
		then `SHIPPED   +${tonumber(payout) or 0}`
		else "LAUNCH FAILED   your components are safe, try again"
	resultLabel.TextColor3 = if shipped then Theme.TYPED else Theme.BUG
	resultLabel.Visible = true
	task.delay(RESULT_SECONDS, function()
		if not renderConnection then
			gui.Enabled = false
		end
	end)
end

local function bar(parent: Instance, color: Color3, order: number): Frame
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 10)
	back.BackgroundColor3 = Theme.PANEL
	back.BorderSizePixel = 0
	back.LayoutOrder = order
	back.Parent = parent
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

function BattleController.Init()
	gui = Theme.Screen("Battle", 6)
	gui.Enabled = false

	root = Theme.Panel(gui, UDim2.fromScale(0.9, 0.82), UDim2.fromScale(0.5, 0.5))
	root.AnchorPoint = Vector2.new(0.5, 0.5)

	rootFlash = Instance.new("Frame")
	rootFlash.Size = UDim2.fromScale(1, 1)
	rootFlash.BackgroundTransparency = 1
	rootFlash.BorderSizePixel = 0
	rootFlash.ZIndex = 8
	rootFlash.Parent = root

	Sfx.Preload()
	Music.Preload()

	-- Left: the client on a live call.
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(0.26, 1)
	left.Parent = root
	Theme.List(left, 8)
	face = Theme.Text(left, "😐", 48)
	face.LayoutOrder = 1
	clientName = Theme.Text(left, "", 16)
	clientName.LayoutOrder = 2
	Theme.Text(left, "ON CALL · LIVE DEMO", 12, Theme.MUTED).LayoutOrder = 3
	bubbleStack = Instance.new("Frame")
	bubbleStack.BackgroundTransparency = 1
	bubbleStack.Size = UDim2.new(1, 0, 0, 0)
	bubbleStack.AutomaticSize = Enum.AutomaticSize.Y
	bubbleStack.LayoutOrder = 7
	bubbleStack.Parent = left
	Theme.List(bubbleStack, 6)
	Theme.Text(left, "CLIENT MOOD", 12, Theme.MUTED).LayoutOrder = 5
	moodFill = bar(left, Theme.MOOD, 6)

	-- Centre: instruction, wave, ship progress, combo, the bug lane and the typing row.
	local centre = Instance.new("Frame")
	centre.BackgroundTransparency = 1
	centre.Position = UDim2.fromScale(0.28, 0)
	centre.Size = UDim2.fromScale(0.72, 1)
	centre.Parent = root

	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 84)
	top.Parent = centre
	Theme.List(top, 4)
	instructionLabel = Theme.Text(top, INSTRUCTION_KEYBOARD, 14, Theme.MOOD)
	instructionLabel.LayoutOrder = 0
	waveLabel = Theme.Text(top, "GET READY", 16, Theme.ACCENT)
	waveLabel.LayoutOrder = 1
	Theme.Text(top, "SHIP PROGRESS", 12, Theme.MUTED).LayoutOrder = 2
	progressFill = bar(top, Theme.TYPED, 3)

	comboLabel = Theme.Text(centre, "x0", 40, Theme.ACCENT)
	comboLabel.Font = Enum.Font.GothamBlack
	comboLabel.AnchorPoint = Vector2.new(1, 0)
	comboLabel.Position = UDim2.new(1, 0, 0, 88)
	comboLabel.Size = UDim2.fromOffset(160, 44)
	comboLabel.AutomaticSize = Enum.AutomaticSize.None
	comboLabel.TextXAlignment = Enum.TextXAlignment.Right

	bugLayer = Instance.new("Frame")
	bugLayer.BackgroundTransparency = 1
	bugLayer.Position = UDim2.fromOffset(0, 150)
	bugLayer.Size = UDim2.new(1, 0, 1, -230)
	bugLayer.Parent = centre

	-- The target: bugs converge on this line. Keep them off it.
	local codeLine = Instance.new("Frame")
	codeLine.AnchorPoint = Vector2.new(0.5, 0)
	codeLine.Position = UDim2.fromScale(0.5, 0)
	codeLine.Size = UDim2.new(0, 4, 1, 0)
	codeLine.BackgroundColor3 = Theme.ACCENT
	codeLine.BackgroundTransparency = 0.35
	codeLine.BorderSizePixel = 0
	codeLine.Parent = bugLayer
	local codeLabel = Theme.Text(bugLayer, "▼ YOUR CODE ▼", 12, Theme.ACCENT)
	codeLabel.AnchorPoint = Vector2.new(0.5, 1)
	codeLabel.Position = UDim2.fromScale(0.5, 0)
	codeLabel.Size = UDim2.fromOffset(140, 16)
	codeLabel.AutomaticSize = Enum.AutomaticSize.None
	codeLabel.TextXAlignment = Enum.TextXAlignment.Center

	inputHolder = Instance.new("Frame")
	inputHolder.BackgroundTransparency = 1
	inputHolder.AnchorPoint = Vector2.new(0, 1)
	inputHolder.Position = UDim2.fromScale(0, 1)
	inputHolder.Size = UDim2.new(1, 0, 0, 64)
	inputHolder.Parent = centre

	resultLabel = Theme.Text(root, "", 30, Theme.TYPED)
	resultLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultLabel.Position = UDim2.fromScale(0.5, 0.62)
	resultLabel.Size = UDim2.fromScale(0.8, 0.2)
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel.ZIndex = 5
	resultLabel.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function BattleController.Start()
	RemoteManager.GetRemote(RemoteNames.BattleStarted).OnClientEvent:Connect(onStarted)
	RemoteManager.GetRemote(RemoteNames.BattleUpdate).OnClientEvent:Connect(onUpdate)
	RemoteManager.GetRemote(RemoteNames.BattleEnded).OnClientEvent:Connect(onEnded)
end

return BattleController
